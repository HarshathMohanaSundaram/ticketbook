class CreateHolds < ActiveRecord::Migration[7.2]
  def change
    create_table :holds do |t|
      t.references :user, null: false, foreign_key: true
      t.references :trip, null: false, foreign_key: true
      t.datetime :expires_at, null: false
      t.string :status, null: false, default: "active"   # active | converted | released | expired
      t.integer :total_paise, null: false, default: 0

      t.timestamps
    end
    # Lets the sweeper find expirable holds without scanning the table.
    add_index :holds, %i[status expires_at]
  end
end
