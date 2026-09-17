# Claims one or more seats on a trip for five minutes.
#
# This is the concurrency-critical path: no two users may hold the same seat, and
# no seat may be sold twice. The mechanism is ordinary Rails pessimistic locking.
#
#   1. SELECT ... FOR UPDATE on the seat rows. The second request to arrive blocks
#      until the first commits, then reads the committed state -- so there is no
#      window in which both see "available".
#   2. ORDER BY id, so two users picking {4A, 4B} and {4B, 4A} queue instead of
#      deadlocking each other.
#   3. SET LOCAL lock_timeout, so a request waits at most half a second before
#      telling the user the seat is contended, rather than pinning a web thread.
#
# The unique index on (trip_id, seat_number) underwrites all of it: one seat is
# one row, so locking the row is the same thing as locking the seat.
class SeatHoldService < ApplicationService
  LOCK_TIMEOUT = "500ms".freeze

  def initialize(user:, trip:, seat_ids:)
    @user = user
    @trip = trip
    @seat_ids = Array(seat_ids).map(&:to_i).uniq
  end

  def call
    return failure(:no_seats_selected) if @seat_ids.empty?
    return failure(:too_many_seats, limit: Hold::MAX_SEATS) if @seat_ids.size > Hold::MAX_SEATS
    return failure(:trip_not_bookable) unless @trip.bookable?

    hold = nil

    ApplicationRecord.transaction do
      ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")

      # Everything is validated before anything is written. `return` inside a
      # transaction block COMMITS in Rails, so an early exit after a write would
      # persist half the work -- releasing this user's existing hold and then
      # bailing out would leave them with nothing.
      own_hold_ids = @user.holds.live.where(trip: @trip).pluck(:id)
      seats = lock_seats(own_hold_ids)
      requested = seats.select { |seat| @seat_ids.include?(seat.id) }

      return failure(:seat_not_found) unless requested.size == @seat_ids.size

      # A seat held by this user's own live hold is theirs to keep: going back and
      # swapping {A,B} for {B,C} must not report B as taken.
      taken = requested.reject { |seat| seat.claimable? || own_hold_ids.include?(seat.hold_id) }
      return failure(:seats_taken, seat_numbers: taken.map(&:seat_number).sort) if taken.any?

      # Past every check, so mutating is safe. The previous hold's seats were
      # locked above, in the same ascending-id pass.
      release_previous_hold(own_hold_ids)

      # The release detached some of these rows through its own AR objects, so
      # our copies are stale. They are still locked by this transaction, so the
      # reload is a cheap re-read of rows nobody else can touch.
      seats = requested.each(&:reload)

      hold = Hold.create!(user: @user, trip: @trip,
                          expires_at: Hold::HOLD_WINDOW.from_now,
                          total_paise: seats.sum(&:price_paise))

      seats.each do |seat|
        # An expired hold is reclaimed in place: held -> available -> held.
        seat.release! if seat.stale_hold?

        # Assign before firing the event, not after. The trip_seats_held_has_a_hold
        # constraint rejects a row that is 'held' with no hold attached, so the
        # status and the hold must land in the same UPDATE.
        seat.assign_attributes(hold: hold, hold_expires_at: hold.expires_at)
        seat.place_hold!
      end
    end

    # Enqueued after the transaction commits (see enqueue_after_transaction_commit),
    # so the worker can never look up a hold that has not landed yet.
    HoldExpiryJob.set(wait_until: hold.expires_at).perform_later(hold.id)

    success(hold)
  rescue ActiveRecord::LockWaitTimeout
    # Someone else's transaction is holding these rows right now.
    failure(:seats_contended)
  end

  private

  # Locks the requested seats AND any seat this user is already holding on this
  # trip, in one ascending-id pass. Two passes would mean acquiring a lower id
  # after a higher one, which is exactly the ordering that deadlocks.
  def lock_seats(own_hold_ids)
    ids = @seat_ids | TripSeat.where(hold_id: own_hold_ids).pluck(:id)
    @trip.trip_seats.where(id: ids).order(:id).lock.to_a
  end

  def release_previous_hold(own_hold_ids)
    Hold.where(id: own_hold_ids).order(:id).lock.each do |hold|
      HoldReleaseService.call(hold: hold, reason: :replaced, locked: true)
    end
  end
end
