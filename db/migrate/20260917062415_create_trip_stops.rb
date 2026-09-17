class CreateTripStops < ActiveRecord::Migration[7.2]
  def change
    create_table :trip_stops do |t|
      t.references :trip, null: false, foreign_key: true
      t.references :stop_point, null: false, foreign_key: true
      # Single table inheritance: BoardingStop | DroppingStop. Making the role a
      # class rather than a string means `booking.dropping_stop = a_boarding_stop`
      # raises AssociationTypeMismatch instead of quietly printing the wrong time.
      t.string :type, null: false
      # Timing is per-trip, not per-place: the 10pm and the 11pm bus reach the
      # same pickup at different times.
      t.datetime :scheduled_at, null: false
      # Named `position`, not `sequence` -- `sequence` collides with FactoryBot's
      # own DSL method and breaks every factory that sets it.
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :trip_stops, %i[trip_id type position]
    # One place can serve both roles on a trip (a mid-route stop picks up and
    # drops off), so the type is part of the key.
    add_index :trip_stops, %i[trip_id stop_point_id type], unique: true,
              name: "index_trip_stops_on_trip_and_point_and_type"
  end
end
