class ReschedulesController < ApplicationController
  before_action :require_authentication
  before_action :set_booking

  # GET /bookings/:booking_id/reschedule/new
  # Lists the other departures on the same route and operator; picking one shows
  # its seat map.
  def new
    unless @booking.reschedulable?
      return redirect_to @booking,
                         alert: "Rescheduling closed at #{l(@booking.cancellation_deadline, format: :day_and_time)}, " \
                                "an hour before departure."
    end

    @alternatives = alternatives
    @target_trip = @alternatives.find { |trip| trip.id == params[:trip_id].to_i }
    @seats = @target_trip&.trip_seats&.numbered&.to_a
  end

  # POST /bookings/:booking_id/reschedule
  def create
    target = alternatives.find { |trip| trip.id == params[:trip_id].to_i }
    return redirect_to new_booking_reschedule_path(@booking), alert: "Pick a departure first." if target.nil?

    result = RescheduleService.call(booking: @booking, target_trip: target,
                                    seat_ids: seat_ids, actor: current_user)

    if result.success?
      redirect_to result.value,
                  notice: result.meta[:replay] ? "This booking was already rescheduled." : "Booking rescheduled."
    else
      redirect_to new_booking_reschedule_path(@booking, trip_id: target.id), alert: message_for(result)
    end
  end

  private

  def set_booking
    @booking = current_user.bookings.find_by!(pnr: params[:booking_id])
  end

  # Same route, same operator, still bookable, not the trip they are on.
  def alternatives
    Trip.bookable
        .between_cities(@booking.trip.origin_city_id, @booking.trip.destination_city_id)
        .where(operator_id: @booking.trip.operator_id)
        .where.not(id: @booking.trip_id)
        .order(:departs_at)
        .preload(:bus, :operator, :origin_city, :destination_city,
                 boarding_stops: :stop_point, dropping_stops: :stop_point)
        .limit(20)
        .to_a
  end

  def seat_ids
    Array(params[:seat_ids]).flat_map { |value| value.to_s.split(",") }.compact_blank
  end

  def message_for(result)
    case result.error
    when :seats_taken         then "Seat #{result.meta[:seat_numbers].to_sentence} was just taken. Please pick another."
    when :seat_count_mismatch then "Pick exactly #{result.meta[:expected]} seat#{'s' if result.meta[:expected] > 1}."
    when :seat_not_found      then "Those seats are not on that departure."
    when :trip_not_bookable   then "That departure is no longer open for booking."
    when :cutoff_passed       then "Rescheduling closed at #{l(result.meta[:deadline], format: :day_and_time)}."
    when :not_confirmed       then "This booking cannot be rescheduled."
    when :same_trip           then "That is the departure you are already on."
    when :different_route, :different_operator
      then "You can only move to another departure on the same route and operator."
    else "Could not reschedule this booking."
    end
  end
end
