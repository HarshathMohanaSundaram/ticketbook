class AddRescheduleIdempotencyIndexToBookings < ActiveRecord::Migration[7.2]
  def change
    # One booking can be rescheduled into at most one successor. Same trick as the
    # unique index on hold_id: a double-submitted reschedule loses the insert race
    # and the service hands back the booking that already exists, rather than
    # creating a second one and releasing the seats twice.
    add_index :bookings, :rescheduled_from_id, unique: true,
              where: "rescheduled_from_id IS NOT NULL",
              name: "index_bookings_on_rescheduled_from_id_unique"
  end
end
