# Returns a hold's seats to the pool. Used when a hold expires (F5), when the
# user abandons it, and when they pick a different set of seats.
#
# Idempotent by design: Sidekiq delivers at least once, so running this twice on
# the same hold must be harmless.
class HoldReleaseService < ApplicationService
  REASONS = %i[expired released replaced].freeze

  def initialize(hold:, reason: :released, locked: false)
    @hold = hold
    @reason = reason
    # The seat-hold path calls this from inside a transaction that already holds
    # the locks; taking them again would be redundant, and opening a nested
    # transaction would hide a rollback.
    @locked = locked
  end

  def call
    # Cheap pre-check to avoid opening a transaction for a hold that is obviously
    # finished. It is only an optimisation -- the authoritative check happens
    # under the row lock below.
    return success(@hold, already: true) unless @hold.active?

    outcome = @locked ? release : ApplicationRecord.transaction { release }

    success(@hold.reload, already: outcome == :stale)
  end

  private

  def release
    # Re-read under the lock. A confirmation may have converted this hold while
    # this job was waiting for the lock, in which case the object we were handed
    # is stale and releasing would overwrite a booked hold's status.
    hold = @locked ? @hold : Hold.lock.find(@hold.id)
    return :stale unless hold.active?

    seats = TripSeat.where(hold_id: hold.id).order(:id)
    seats = seats.lock unless @locked

    seats.each do |seat|
      # Same rule in reverse: clear the hold in the same UPDATE that moves the
      # seat back to available. A booked seat belongs to a booking now -- only
      # detach it from the hold, never release it.
      seat.assign_attributes(hold_id: nil, hold_expires_at: nil)
      seat.held? ? seat.release! : seat.save!
    end

    hold.update!(status: @reason == :expired ? "expired" : "released")
    :released
  end
end
