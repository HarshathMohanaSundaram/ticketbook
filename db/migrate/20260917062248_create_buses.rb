class CreateBuses < ActiveRecord::Migration[7.2]
  def change
    create_table :buses do |t|
      t.references :operator, null: false, foreign_key: true
      t.string :registration_number, null: false
      t.string :bus_type, null: false               # ac | non_ac
      t.string :berth_type, null: false             # sleeper | seater
      t.integer :seats_total, null: false, default: 0
      # A closed, filterable set, so a text array with a GIN index beats jsonb:
      # `amenity_codes @> ARRAY['wifi']` is one index hit and one readable scope.
      t.string :amenity_codes, array: true, null: false, default: []

      t.timestamps
    end
    add_index :buses, :registration_number, unique: true
    add_index :buses, %i[bus_type berth_type]
    add_index :buses, :amenity_codes, using: :gin
  end
end
