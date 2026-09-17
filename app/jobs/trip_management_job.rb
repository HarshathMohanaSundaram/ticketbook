# Keeps trip state honest, every fifteen minutes.
#
# Nothing in here is load-bearing. Seat availability is already correct without
# it -- TripSeat#claimable? treats an expired hold as free inside the row lock --
# and the bookable scope filters trips by time rather than by status. This job
# makes the stored data agree with reality so the seat map, the trip list and a
# psql session all tell the same story.
#
# Each task is isolated: one failing chore must not stop the others, and a retry
# must not be blocked by an unrelated error.
class TripManagementJob < ApplicationJob
  queue_as :critical

  TASKS = %i[release_expired_holds mark_departed_trips].freeze
  BATCH_SIZE = 1_000

  def perform
    results = TASKS.index_with do |task|
      begin
        send(task)
      rescue StandardError => e
        Rails.logger.error("[TripManagement] #{task} failed: #{e.class}: #{e.message}")
        Sentry.capture_exception(e) if defined?(Sentry)
        :failed
      end
    end

    Rails.logger.info("[TripManagement] #{results.map { |task, n| "#{task}=#{n}" }.join(' ')}")
    results
  end

  private

  # Holds whose scheduled expiry job never ran -- a Redis flush, a worker killed
  # mid-run, a deploy that dropped the scheduled set.
  def release_expired_holds
    ids = Hold.expirable.limit(BATCH_SIZE).pluck(:id)
    ids.each { |id| HoldExpiryJob.perform_later(id) }
    ids.size
  end

  # A bus that has left is no longer "scheduled". Nothing reads this status in the
  # booking path, but an operator listing trips by status should see the truth.
  def mark_departed_trips
    Trip.scheduled.where(departs_at: ...Time.current).update_all(status: "departed", updated_at: Time.current)
  end
end
