class CreateStopPoints < ActiveRecord::Migration[7.2]
  def change
    create_table :stop_points do |t|
      t.references :city, null: false, foreign_key: true
      # Optional: a point can be shared across operators (a bus stand) or
      # specific to one (an operator's own office).
      t.references :operator, null: true, foreign_key: true
      t.string :name, null: false
      t.string :landmark
      t.string :address

      t.timestamps
    end
  end
end
