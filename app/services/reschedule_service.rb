# Moves a confirmed booking onto another departure of the same route and operator.
#
# Done as one transaction rather than hold -> confirm -> release, because those
# are three separate commits: a crash between the second and the third would
# leave two live bookings holding two sets of seats. Either the swap happens
# whole or it does not happen.
#
# The original booking is never touched until every rule has passed, which matters
# because `return` inside a transaction commits rather than rolling back.
class RescheduleService < ApplicationService
  def initialize(booking:, target_trip:, seat_ids:, actor:, at: Time.current)
    @booking = booking
    @target_trip = target_trip
    @seat_ids = Array(seat_ids).map(&:to_i).uniq
    @actor = actor
    @at = at
  end

  def call
    # A reschedule that already happened: hand back the successor rather than
    # making a second one.
    if (existing = Booking.find_by(rescheduled_from_id: @booking.id))
      return success(existing, replay: true)
    end

    new_booking = nil

    ApplicationRecord.transaction do
      old = Booking.lock.find(@booking.id)

      # Double-checked under the lock, like BookingConfirmationService: a
      # concurrent request may have finished while we waited for it.
      if (existing = Booking.find_by(rescheduled_from_id: old.id))
        return success(existing, replay: true)
      end

      error = rule_violation(old)
      return failure(error, **failure_meta(error, old)) if error

      seats = @target_trip.trip_seats.where(id: @seat_ids).order(:id).lock.to_a
      return failure(:seat_not_found) unless seats.size == @seat_ids.size

      taken = seats.reject(&:claimable?)
      return failure(:seats_taken, seat_numbers: taken.map(&:seat_number).sort) if taken.any?

      new_booking = issue_booking(old, seats)
      release(old)
    end

    # Both ends move: seats freed on the old departure, taken on the new one.
    AvailabilityCache.touch!(@booking.trip)
    AvailabilityCache.touch!(@target_trip)

    success(new_booking)
  rescue ActiveRecord::RecordNotUnique
    # Two reschedules raced past both checks; the index picked a winner.
    success(Booking.find_by!(rescheduled_from_id: @booking.id), replay: true)
  end

  private

  def rule_violation(old)
    return :forbidden          unless old.user_id == @actor.id
    return :not_confirmed      unless old.confirmed?
    return :cutoff_passed      unless old.cancellable?(@at)
    return :same_trip          if @target_trip.id == old.trip_id
    return :different_route    unless same_route?(old)
    return :different_operator unless @target_trip.operator_id == old.trip.operator_id
    return :trip_not_bookable  unless @target_trip.bookable?
    return :seat_count_mismatch unless @seat_ids.size == old.tickets.count

    nil
  end

  def failure_meta(error, old)
    case error
    when :cutoff_passed       then { deadline: old.cancellation_deadline }
    when :seat_count_mismatch then { expected: old.tickets.count }
    else {}
    end
  end

  def same_route?(old)
    @target_trip.origin_city_id == old.trip.origin_city_id &&
      @target_trip.destination_city_id == old.trip.destination_city_id
  end

  def issue_booking(old, seats)
    booking = Booking.create!(
      user: old.user, trip: @target_trip, rescheduled_from: old,
      pnr: Booking.generate_pnr, status: "confirmed",
      total_paise: seats.sum(&:price_paise), departs_at: @target_trip.departs_at,
      boarding_stop: matching_stop(old.boarding_stop, @target_trip.boarding_stops),
      dropping_stop: matching_stop(old.dropping_stop, @target_trip.dropping_stops)
    )

    now = Time.current
    Ticket.insert_all!(
      old.tickets.order(:id).zip(seats).map do |ticket, seat|
        { booking_id: booking.id, trip_seat_id: seat.id,
          passenger_name: ticket.passenger_name, passenger_age: ticket.passenger_age,
          gender: ticket.gender, price_paise: seat.price_paise,
          created_at: now, updated_at: now }
      end
    )

    seats.each do |seat|
      # A seat whose hold expired is claimable but still reads 'held'; put it back
      # to available before booking it, exactly as SeatHoldService does.
      seat.release! if seat.stale_hold?
      seat.book!
    end

    booking
  end

  def release(old)
    old.trip_seats.order(:id).lock.each do |seat|
      # Tickets stay behind as history -- they become past_tickets on the seat.
      seat.release! if seat.booked?
    end
    old.update!(status: "rescheduled")
  end

  # Keep the passenger's pickup point if the new trip stops at the same place,
  # otherwise fall back to its first stop.
  def matching_stop(previous, candidates)
    return candidates.first if previous.nil?

    candidates.find { |stop| stop.stop_point_id == previous.stop_point_id } || candidates.first
  end
end
