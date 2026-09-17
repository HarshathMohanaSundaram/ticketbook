class EnableCitext < ActiveRecord::Migration[7.2]
  def change
    # Makes users.email compare case-insensitively, so Ravi@x.com and ravi@x.com
    # are one account rather than two.
    enable_extension "citext"
  end
end
