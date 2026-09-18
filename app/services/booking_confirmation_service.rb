# Converts a live hold into a booking.
#
# The idempotency requirement -- refreshing must not create a second booking --
# is met by two guards that cover different races:
#
#   1. A fast path that finds an existing booking for the hold and returns it.
#      This catches the ordinary refresh without touching the write path.
#   2. The unique index on bookings.hold_id. Two requests arriving in the same
#      millisecond both find nothing on the fast path and both try to insert;
#      Postgres picks a winner and the loser returns the winner's booking.
#
# Neither alone is sufficient. Together there is no path to a duplicate.
class BookingConfirmationService < ApplicationService
  def initialize(user:, hold:, passengers:, boarding_stop_id: nil, dropping_stop_id: nil)
    @user = user
    @hold = hold
    @passengers = Array(passengers)
    @boarding_stop_id = boarding_stop_id
    @dropping_stop_id = dropping_stop_id
  end

  def call
    if (existing = Booking.find_by(hold_id: @hold.id))
      return success(existing, replay: true)
    end

    booking = nil

    ApplicationRecord.transaction do
      # Locking the hold stops HoldExpiryJob releasing it mid-confirmation: the
      # two serialise, and whichever commits first wins.
      hold = Hold.lock.find(@hold.id)

      # Double-checked: a concurrent confirmation may have finished while this
      # request was blocked on the lock above, converting the hold. Without this
      # the loser would report :hold_expired instead of the booking that now
      # exists -- technically no duplicate, but the wrong answer.
      if (existing = Booking.find_by(hold_id: hold.id))
        return success(existing, replay: true)
      end

      return failure(:forbidden) unless hold.user_id == @user.id
      return failure(:hold_expired) unless hold.live?

      # Same ascending-id lock order as SeatHoldService, so a hold and a
      # confirmation can never deadlock each other.
      seats = hold.trip_seats.order(:id).lock.to_a
      return failure(:hold_expired) if seats.empty? || seats.any? { |seat| !seat.held? }

      # Everything is validated before anything is written -- an early return
      # inside a transaction commits rather than rolling back.
      return failure(:passenger_count_mismatch, expected: seats.size) unless @passengers.size == seats.size
      return failure(:passenger_name_missing) if @passengers.any? { |p| p[:name].to_s.strip.blank? }

      stops = resolve_stops(hold.trip)
      return failure(:stop_not_on_trip) if stops.nil?

      booking = create_booking!(hold, seats, stops)
      Ticket.insert_all!(ticket_rows(booking, seats))

      seats.each do |seat|
        seat.assign_attributes(hold_id: nil, hold_expires_at: nil)
        seat.confirm!
      end

      hold.update!(status: "converted")
    end

    # After the commit, never inside it: a rolled back booking must not invalidate
    # anything. Search results are cached; seat availability never is, so this
    # only matters for a list that might now show a sold-out trip.
    AvailabilityCache.touch!(booking.trip)

    success(booking)
  rescue ActiveRecord::RecordNotUnique
    # Two confirmations raced past the fast path. One inserted; this is the other.
    success(Booking.find_by!(hold_id: @hold.id), replay: true)
  end

  private

  # Scoped through the trip's own stops, so a stop id from another departure
  # cannot be smuggled in through the form.
  def resolve_stops(trip)
    boarding = trip.boarding_stops.find_by(id: @boarding_stop_id)
    dropping = trip.dropping_stops.find_by(id: @dropping_stop_id)
    return nil if @boarding_stop_id.present? && boarding.nil?
    return nil if @dropping_stop_id.present? && dropping.nil?

    { boarding_stop: boarding, dropping_stop: dropping }
  end

  PNR_ATTEMPTS = 3

  def create_booking!(hold, seats, stops)
    attempts = 0

    begin
      # requires_new opens a SAVEPOINT. Postgres aborts the whole transaction on a
      # failed statement, so without it a retry would die with "current transaction
      # is aborted" instead of trying a second PNR.
      Booking.transaction(requires_new: true) do
        Booking.create!(
          user: @user, trip: hold.trip, hold: hold, pnr: Booking.generate_pnr,
          status: "confirmed", total_paise: seats.sum(&:price_paise),
          departs_at: hold.trip.departs_at, **stops
        )
      end
    rescue ActiveRecord::RecordInvalid => e
      # The uniqueness validation runs a SELECT and fails before the INSERT, so a
      # PNR collision usually arrives as RecordInvalid, not RecordNotUnique.
      raise unless e.record.errors.of_kind?(:pnr, :taken)

      attempts += 1
      retry if attempts < PNR_ATTEMPTS
      raise
    rescue ActiveRecord::RecordNotUnique => e
      # Two requests generated the same PNR in the same instant, so the validation
      # passed for both and the index caught the loser. A hold_id collision is a
      # different thing entirely -- the idempotency race -- and belongs to #call.
      raise if e.message.include?("hold_id")

      attempts += 1
      retry if attempts < PNR_ATTEMPTS
      raise
    end
  end

  def ticket_rows(booking, seats)
    now = Time.current
    seats.each_with_index.map do |seat, index|
      passenger = @passengers[index]
      {
        booking_id: booking.id, trip_seat_id: seat.id,
        passenger_name: passenger[:name].to_s.strip,
        passenger_age: passenger[:age].presence,
        gender: passenger[:gender].presence,
        price_paise: seat.price_paise,
        created_at: now, updated_at: now
      }
    end
  end
end
