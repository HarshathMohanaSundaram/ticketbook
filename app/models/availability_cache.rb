# A generation counter per corridor-day, used to expire cached search results.
#
# Why a counter rather than deleting keys: a search key includes a digest of the
# filters, so "Bangalore to Chennai on the 19th" has hundreds of variants --
# AC + wifi + a price band + sorted by rating, and so on. Those keys cannot be
# enumerated, so they cannot be deleted. Incrementing one counter makes every one
# of them unreachable at once, and the orphans expire on their own TTL.
#
#   key   = ["trip_search", ..., AvailabilityCache.version_for(...)]
#   bump  = AvailabilityCache.touch!(trip)   # the old keys are never read again
module AvailabilityCache
  NAMESPACE = "avail:v1".freeze
  # Counters outlive the searches they invalidate; a week is plenty since trips
  # are seeded a week ahead.
  RETENTION = 7.days

  class << self
    def version_for(origin_city_id, destination_city_id, date)
      Rails.cache.read(key(origin_city_id, destination_city_id, date), raw: true).to_i
    end

    # Called after commit, never inside a transaction: a rolled back booking must
    # not invalidate anything.
    def touch!(trip)
      Rails.cache.increment(key(trip.origin_city_id, trip.destination_city_id, trip.service_date),
                            1, raw: true, expires_in: RETENTION, initial: 0)
    end

    def key(origin_city_id, destination_city_id, date)
      "#{NAMESPACE}:#{origin_city_id}:#{destination_city_id}:#{date}"
    end
  end
end
