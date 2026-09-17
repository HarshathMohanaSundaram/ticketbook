# Composes the scopes on Trip into one relation. No params, no rendering -- it
# takes a validated form and hands back trips, which is what makes it the right
# seam for the F9 cache to wrap.
class TripSearchQuery
  MAX_RESULTS = 200

  def initialize(form)
    @form = form
  end

  def call
    return Trip.none unless @form.searchable?

    # preload rather than includes: the rating sort joins operators, and mixing
    # a join with includes on the same table makes Rails build one big query
    # with aliased columns. Two small queries are cheaper and easier to read.
    # Cities are preloaded too: the result card prints both names, which without
    # this is two extra queries per row.
    filtered.preload(:operator, :bus, :origin_city, :destination_city).limit(MAX_RESULTS)
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
