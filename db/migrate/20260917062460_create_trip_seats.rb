class CreateTripSeats < ActiveRecord::Migration[7.2]
  def change
    create_table :trip_seats do |t|
      t.references :trip, null: false, foreign_key: true
      # Set while the seat is held. The booking link goes through tickets.
      t.references :hold, null: true, foreign_key: true
      t.string :seat_number, null: false
      t.string :status, null: false, default: "available"  # available | held | booked | blocked
      t.string :berth_type, null: false                    # sleeper | seater
      t.integer :price_paise, null: false
      # Denormalised from the hold so `claimable?` can answer inside the row lock
      # without a join -- which is what lets an expired hold be reclaimed even
      # when the background job has not run.
      t.datetime :hold_expires_at

      t.timestamps
    end
    # The index that makes overselling impossible: one row per seat per trip, and
    # that row can only carry one status at a time.
    add_index :trip_seats, %i[trip_id seat_number], unique: true
    add_index :trip_seats, %i[trip_id status]
    add_index :trip_seats, :hold_id, where: "hold_id IS NOT NULL", name: "index_trip_seats_on_active_hold"
  end
end
