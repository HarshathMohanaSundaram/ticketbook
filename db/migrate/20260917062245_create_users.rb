class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.citext :email, null: false
      t.string :name
      t.string :phone

      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
