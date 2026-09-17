class CreateTrips < ActiveRecord::Migration[7.2]
  def change
    create_table :trips do |t|
      t.references :operator, null: false, foreign_key: true
      t.references :bus, null: false, foreign_key: true
      # Cities sit directly on the trip: the search triple (from, to, date) then
      # resolves against one composite index instead of a join through routes.
      t.references :origin_city, null: false, foreign_key: { to_table: :cities }
      t.references :destination_city, null: false, foreign_key: { to_table: :cities }
      t.datetime :departs_at, null: false
      t.datetime :arrives_at, null: false
      t.integer :base_fare_paise, null: false
      t.string :status, null: false, default: "scheduled"  # scheduled | departed | cancelled
      t.integer :seats_total, null: false, default: 0
      # Advisory counter for display only. Availability is always counted off
      # trip_seats; nothing in the booking path may trust this column.
      t.integer :seats_available, null: false, default: 0

      t.timestamps
    end
    add_index :trips, %i[origin_city_id destination_city_id departs_at], name: "index_trips_on_search_triple"
    add_index :trips, %i[operator_id departs_at]
    add_index :trips, :departs_at
  end
end
