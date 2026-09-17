class HoldsController < ApplicationController
  before_action :require_authentication
  before_action :set_hold, only: %i[show destroy]

  # POST /trips/:trip_id/holds
  def create
    trip = Trip.find(params[:trip_id])
    result = SeatHoldService.call(user: current_user, trip: trip, seat_ids: seat_ids)

    if result.success?
      redirect_to result.value
    else
      redirect_to trip, alert: hold_error_message(result)
    end
  end

  def show
    # An expired hold is not an error -- it is the expected end of the window.
    return redirect_to @hold.trip, alert: "Your hold expired. Please pick seats again." unless @hold.live?

    @trip = @hold.trip
    @seats = @hold.trip_seats.numbered
  end

  # DELETE /holds/:id -- the user changed their mind before the timer ran out.
  def destroy
    HoldReleaseService.call(hold: @hold, reason: :released)
    redirect_to @hold.trip, notice: "Seats released.", status: :see_other
  end

  private

  def set_hold
    # Scoped to the current user: a hold id in someone else's URL is a 404, not
    # a 403, so it does not confirm the hold exists.
    @hold = current_user.holds.find(params[:id])
  end

  def seat_ids
    Array(params[:seat_ids]).flat_map { |value| value.to_s.split(",") }.compact_blank
  end

  def hold_error_message(result)
    case result.error
    when :no_seats_selected then "Pick at least one seat."
    when :too_many_seats    then "You can hold at most #{result.meta[:limit]} seats at a time."
    when :trip_not_bookable then "This trip is no longer open for booking."
    when :seat_not_found    then "Those seats are not on this trip."
    when :seats_taken       then "Seat #{result.meta[:seat_numbers].to_sentence} was just taken. Please pick another."
    when :seats_contended   then "Someone is booking those seats right now. Please try again."
    else "Could not hold those seats."
    end
  end
end
