class CreateDrivers < ActiveRecord::Migration[7.2]
  def change
    create_table :drivers do |t|
      # Drivers are staff of one operator, exactly as buses are its fleet.
      t.references :operator, null: false, foreign_key: true
      t.string :name, null: false
      t.string :phone
      t.string :licence_number, null: false
      t.date :licence_expires_on

      t.timestamps
    end
    add_index :drivers, :licence_number, unique: true
  end
end
