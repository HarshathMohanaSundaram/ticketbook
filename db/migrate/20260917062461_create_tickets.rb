class CreateTickets < ActiveRecord::Migration[7.2]
  def change
    create_table :tickets do |t|
      t.references :booking, null: false, foreign_key: true
      t.references :trip_seat, null: false, foreign_key: true
      t.string :passenger_name, null: false
      t.integer :passenger_age
      t.string :gender
      t.integer :price_paise, null: false

      t.timestamps
    end
    # One passenger per seat per booking.
    add_index :tickets, %i[booking_id trip_seat_id], unique: true
  end
end
