class CreateCities < ActiveRecord::Migration[7.2]
  def change
    create_table :cities do |t|
      t.string :name, null: false
      t.string :state, null: false
      t.string :slug, null: false

      t.timestamps
    end
    add_index :cities, :slug, unique: true
  end
end
