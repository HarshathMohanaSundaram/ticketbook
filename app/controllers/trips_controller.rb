class TripsController < ApplicationController
  # Browsing is public. Authentication starts at the seat hold, which is where a
  # record first belongs to somebody.

  def index
    @cities = City.alphabetical
    @form = TripSearchForm.new(search_params)
    query = TripSearchQuery.new(@form)
    @trips = query.call.to_a
    @empty_reason = query.empty_reason if @trips.empty?
    @available_counts = TripSeat.available_counts_by_trip(@trips.map(&:id))
  end

  def show
    @trip = Trip.preload(:operator, :bus,
                         boarding_stops: :stop_point,
                         dropping_stops: :stop_point).find(params[:id])
    @seats = @trip.trip_seats.numbered.to_a
    @available_count = @seats.count(&:claimable?)
  end

  private

  def search_params
    params.permit(:from, :to, :date, :bus_type, :berth_type,
                  :min_price, :max_price, :min_rating, :sort, amenities: [])
          .to_h.symbolize_keys
  end
end
