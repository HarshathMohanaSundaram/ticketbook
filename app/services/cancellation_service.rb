# Cancels a confirmed booking and puts its seats back on sale.
#
# Two rules from the brief, both enforced here rather than in the controller so
# that the API, an admin tool and the UI cannot disagree:
#
#   * cancellation is allowed only up to an hour before departure
#   * the refund is the fare less a flat fifty rupees, never below zero
#
# Idempotent: cancelling twice returns the first cancellation rather than
# refunding again. The refund figure is computed once and stored.
class CancellationService < ApplicationService
  def initialize(booking:, actor:, at: Time.current)
    @booking = booking
    @actor = actor
    # One clock for the whole operation, so the rule that was checked and the
    # timestamp that was stored describe the same instant.
    @at = at
  end

  def call
    booking = nil

    ApplicationRecord.transaction do
      booking = Booking.lock.find(@booking.id)

      return failure(:forbidden) unless booking.user_id == @actor.id
      # A second click, or a retry: hand back the cancellation that already happened.
      return success(booking, replay: true) if booking.cancelled?
      return failure(:not_confirmed) unless booking.confirmed?
      return failure(:cutoff_passed, deadline: booking.cancellation_deadline) unless booking.cancellable?(@at)

      # Everything validated; only now write.
      booking.update!(status: "cancelled", cancelled_at: @at,
                      refund_paise: booking.projected_refund_paise)

      release_seats(booking)
    end

    success(booking)
  end

  private

  # Ascending id, the same order SeatHoldService and BookingConfirmationService
  # use, so a cancellation can never deadlock against a hold or a confirmation.
  def release_seats(booking)
    booking.trip_seats.order(:id).lock.each do |seat|
      # Tickets stay as history; the seat simply goes back on sale.
      seat.release! if seat.booked?
    end
  end
end
