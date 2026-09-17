class AddDriversToTrips < ActiveRecord::Migration[7.2]
  def change
    # Both nullable: a trip can be scheduled before the roster is assigned, and a
    # short run needs no relief driver. Long routes legally need the second one.
    add_reference :trips, :driver, null: true, foreign_key: { to_table: :drivers }
    add_reference :trips, :relief_driver, null: true, foreign_key: { to_table: :drivers }

    # A driver cannot be their own relief.
    add_check_constraint :trips, "relief_driver_id IS NULL OR relief_driver_id <> driver_id",
                         name: "trips_relief_driver_differs"
  end
end
