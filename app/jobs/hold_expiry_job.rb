# Releases one hold when its five minutes are up.
#
# This job is housekeeping, not correctness. TripSeat#claimable? already treats a
# hold past its expiry as free, checked inside the row lock -- so a seat is never
# permanently stuck even if Sidekiq is down. What the job buys is a seat map that
# tells the truth without waiting for someone to click the seat.
class HoldExpiryJob < ApplicationJob
  queue_as :critical

  # The hold was deleted; there is nothing to release and retrying will not help.
  discard_on ActiveRecord::RecordNotFound

  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 5

  def perform(hold_id)
    hold = Hold.find(hold_id)

    # Sidekiq delivers at least once, and a hold may have been confirmed into a
    # booking or released by the user in the meantime.
    return unless hold.active?

    # Ran early -- clock skew between the web and worker hosts, or a job fired by
    # the sweeper a moment too soon. Releasing now would steal a live hold.
    if hold.expires_at.future?
      self.class.set(wait_until: hold.expires_at + 2.seconds).perform_later(hold_id)
      return
    end

    HoldReleaseService.call(hold: hold, reason: :expired)
  end
end
