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

      # Picking different seats after going back: the previous hold is released
      # inside the same transaction, so the user never holds two sets at once.
      release_previous_hold

      seats = lock_seats
      return failure(:seat_not_found) unless seats.size == @seat_ids.size

      taken = seats.reject(&:claimable?)
      return failure(:seats_taken, seat_numbers: taken.map(&:seat_number).sort) if taken.any?

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

    success(hold)
  rescue ActiveRecord::LockWaitTimeout
    # Someone else's transaction is holding these rows right now.
    failure(:seats_contended)
  end

  private

  # ORDER BY id is what stops overlapping multi-seat requests deadlocking.
  def lock_seats
    @trip.trip_seats.where(id: @seat_ids).order(:id).lock.to_a
  end

  def release_previous_hold
    previous = @user.holds.live.where(trip: @trip).order(:id).lock.to_a
    previous.each { |hold| HoldReleaseService.call(hold: hold, reason: :replaced, locked: true) }
  end
end
