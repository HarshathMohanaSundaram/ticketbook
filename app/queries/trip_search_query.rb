# Composes the scopes on Trip into one relation. No params, no rendering -- it
# takes a validated form and hands back trips, which is what makes it the right
# seam for the F9 cache to wrap.
class TripSearchQuery
  MAX_RESULTS = 200
  TTL = 10.minutes
  # Bump when the shape of what is cached changes, so old entries are ignored
  # rather than deserialised into something unexpected.
  CACHE_VERSION = "v1".freeze

  def initialize(form)
    @form = form
  end

  def call
    return Trip.none unless @form.searchable?

    # Only the ordered ids are cached, never the records. Marshalled models go
    # stale -- a repriced trip would serve yesterday's fare -- and they bloat
    # Redis. Ids are tiny, and the rows behind them are read fresh every time, so
    # the expensive part (filter and sort over the whole corridor) is skipped
    # while the data stays current.
    ids = Rails.cache.fetch(cache_key, expires_in: TTL, race_condition_ttl: 5.seconds) do
      filtered.limit(MAX_RESULTS).pluck(:id)
    end

    return Trip.none if ids.empty?

    # preload rather than includes: the rating sort joins operators, and mixing a
    # join with includes on the same table makes Rails build one aliased mega
    # query. Cities are preloaded because the result card prints both names.
    Trip.where(id: ids)
        .preload(:operator, :bus, :origin_city, :destination_city)
        .in_order_of(:id, ids)
  end

  # Exposed so a spec can assert what varies the key, and what does not.
  def cache_key
    [
      "trip_search", CACHE_VERSION,
      @form.origin_city.id, @form.destination_city.id, @form.date.to_s,
      filters_digest,
      AvailabilityCache.version_for(@form.origin_city.id, @form.destination_city.id, @form.date)
    ].join("/")
  end

  # Why did this search come back empty? "No buses" is true but unhelpful when the
  # buses exist and have simply left for the day -- a user who was looking at one
  # of them a minute ago reads that as a bug.
  #
  # Only runs when there are no results, so it costs nothing on the happy path.
  def empty_reason
    return nil unless @form.searchable?

    on_route = Trip.between_cities(@form.origin_city.id, @form.destination_city.id).on_date(@form.date)

    return :no_service   if on_route.none?
    return :all_departed if on_route.bookable.none?

    :filtered_out
  end

  private

  # filter_attributes sorts its amenities and drops blanks, so [wifi, cctv] and
  # [cctv, wifi] are one cache entry rather than two.
  def filters_digest
    Digest::MD5.hexdigest(@form.filter_attributes.sort.to_s)
  end

  def filtered
    scope = Trip.bookable
                .between_cities(@form.origin_city.id, @form.destination_city.id)
                .on_date(@form.date)
                .of_bus_type(@form.bus_type)
                .of_berth_type(@form.berth_type)
                .with_amenities(@form.amenities)
                .rated_at_least(@form.min_rating)
                .priced_between(@form.min_price_paise, @form.max_price_paise)

    ordered(scope)
  end

  def ordered(scope)
    case @form.sort
    when "price_low"  then scope.order(base_fare_paise: :asc, departs_at: :asc)
    when "price_high" then scope.order(base_fare_paise: :desc, departs_at: :asc)
    when "rating"     then scope.joins(:operator).order("operators.rating DESC, trips.departs_at ASC")
    when "duration"   then scope.order(Arel.sql("(arrives_at - departs_at) ASC"), departs_at: :asc)
    else scope.order(departs_at: :asc)
    end
  end
end
