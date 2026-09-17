class CreateOperators < ActiveRecord::Migration[7.2]
  def change
    create_table :operators do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.decimal :rating, precision: 2, scale: 1, null: false, default: 0.0
      t.integer :ratings_count, null: false, default: 0

      t.timestamps
    end
    add_index :operators, :slug, unique: true
    add_index :operators, :rating
  end
end
