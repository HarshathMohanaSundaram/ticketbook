class CancellationsController < ApplicationController
  before_action :require_authentication

  # POST /bookings/:booking_id/cancellation
  def create
    booking = current_user.bookings.find_by!(pnr: params[:booking_id])
    result = CancellationService.call(booking: booking, actor: current_user)

    if result.success?
      redirect_to result.value, notice: notice_for(result.value, result)
    else
      redirect_to booking, alert: alert_for(result)
    end
  end

  private

  def notice_for(booking, result)
    return "This booking was already cancelled." if result.meta[:replay]

    "Booking cancelled. #{helpers.number_to_currency(booking.refund_paise / 100.0, unit: '₹', precision: 0)} " \
      "will be refunded."
  end

  def alert_for(result)
    case result.error
    when :cutoff_passed
      "Cancellation closed at #{l(result.meta[:deadline], format: :time_of_day)}, an hour before departure."
    when :not_confirmed then "This booking cannot be cancelled."
    when :forbidden     then "That booking is not yours."
    else "Could not cancel this booking."
    end
  end
end
