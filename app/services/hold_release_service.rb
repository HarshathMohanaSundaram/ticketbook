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
    return success(@hold, already: true) unless @hold.active?

    @locked ? release : ApplicationRecord.transaction { release }

    success(@hold)
  end

  private

  def release
    seats = TripSeat.where(hold_id: @hold.id).order(:id)
    seats = seats.lock unless @locked

    seats.each do |seat|
      # Same rule in reverse: clear the hold in the same UPDATE that moves the
      # seat back to available. A booked seat belongs to a booking now -- only
      # detach it from the hold, never release it.
      seat.assign_attributes(hold_id: nil, hold_expires_at: nil)
      seat.held? ? seat.release! : seat.save!
    end

    @hold.update!(status: @reason == :expired ? "expired" : "released")
  end
end
