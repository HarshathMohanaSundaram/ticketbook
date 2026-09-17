class BookingsController < ApplicationController
  before_action :require_authentication

  # GET /holds/:hold_id/booking/new -- passenger details and pickup points.
  def new
    @hold = current_user.holds.find(params[:hold_id])
    return redirect_to @hold.trip, alert: "Your hold expired. Please pick seats again." unless @hold.live?

    @trip = @hold.trip
    @seats = @hold.trip_seats.numbered
  end

  # POST /holds/:hold_id/booking
  def create
    @hold = current_user.holds.find(params[:hold_id])
    result = BookingConfirmationService.call(
      user: current_user, hold: @hold, passengers: passengers,
      boarding_stop_id: params[:boarding_stop_id], dropping_stop_id: params[:dropping_stop_id]
    )

    if result.success?
      # Redirect after POST, so a refresh re-GETs the ticket rather than
      # re-submitting. The unique index handles the case where it does anyway.
      redirect_to result.value, notice: booking_notice(result)
    else
      redirect_back_on_failure(result)
    end
  end

  def index
    @bookings = current_user.bookings.recent_first.preload(:trip, trip: %i[operator origin_city destination_city])
  end

  def show
    @booking = current_user.bookings.find_by!(pnr: params[:id])
    @tickets = @booking.tickets.preload(:trip_seat)
    @trip = @booking.trip
  end

  private

  # passengers[0][name], passengers[1][name] ... one per held seat.
  def passengers
    params.fetch(:passengers, {}).to_unsafe_h.values.map do |attrs|
      { name: attrs["name"], age: attrs["age"], gender: attrs["gender"] }
    end
  end

  def booking_notice(result)
    result.meta[:replay] ? "This booking was already confirmed." : "Booking confirmed."
  end

  def redirect_back_on_failure(result)
    message =
      case result.error
      when :hold_expired             then "Your hold expired before the booking was confirmed."
      when :forbidden                then "That hold is not yours."
      when :passenger_count_mismatch then "Please give a passenger name for each seat."
      when :passenger_name_missing   then "Every passenger needs a name."
      when :stop_not_on_trip         then "Those boarding points are not on this trip."
      else "Could not confirm the booking."
      end

    if result.error == :hold_expired
      redirect_to @hold.trip, alert: message
    else
      redirect_to new_hold_booking_path(@hold), alert: message
    end
  end
end
