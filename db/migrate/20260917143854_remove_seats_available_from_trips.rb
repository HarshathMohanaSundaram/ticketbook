class RemoveSeatsAvailableFromTrips < ActiveRecord::Migration[7.2]
  def change
    # Nothing maintains this counter and nothing may read it. Keeping it accurate
    # would mean writing to the trips row inside the seat-hold transaction, which
    # would serialise every concurrent hold on a trip behind one row lock --
    # exactly the contention the per-seat locking exists to avoid. Availability is
    # counted off trip_seats instead, in one grouped query per page.
    remove_check_constraint :trips, "seats_available BETWEEN 0 AND seats_total",
                            name: "trips_seats_available_in_range"
    remove_column :trips, :seats_available, :integer, null: false, default: 0
  end
end
