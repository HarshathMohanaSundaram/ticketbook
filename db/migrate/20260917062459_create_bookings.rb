class CreateBookings < ActiveRecord::Migration[7.2]
  def change
    create_table :bookings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :trip, null: false, foreign_key: true
      # The hold this booking was converted from. Nullable only so a booking can
      # outlive a purged hold; the unique index on it is the idempotency guarantee.
      t.references :hold, null: true, foreign_key: true
      t.references :boarding_stop, null: true, foreign_key: { to_table: :trip_stops }
      t.references :dropping_stop, null: true, foreign_key: { to_table: :trip_stops }
      t.references :rescheduled_from, null: true, foreign_key: { to_table: :bookings }
      t.string :pnr, null: false
      t.string :status, null: false, default: "confirmed"  # confirmed | cancelled | rescheduled
      t.integer :total_paise, null: false
      # Snapshot of the trip's departure: survives a trip edit and is what the
      # one-hour cancellation cutoff is measured against.
      t.datetime :departs_at, null: false
      t.datetime :cancelled_at
      t.integer :refund_paise

      t.timestamps
    end
    add_index :bookings, :pnr, unique: true
    add_index :bookings, %i[user_id created_at]
  end
end
