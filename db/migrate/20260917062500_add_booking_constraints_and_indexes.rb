class AddBookingConstraintsAndIndexes < ActiveRecord::Migration[7.2]
  def change
    # ---- The idempotency guarantee -------------------------------------------
    # One hold converts into at most one booking. Two confirm requests arriving in
    # the same millisecond both pass the "already booked?" check and both try to
    # insert; this index makes the loser fail with RecordNotUnique, which the
    # service catches and answers with the winner's booking.
    add_index :bookings, :hold_id, unique: true, where: "hold_id IS NOT NULL",
              name: "index_bookings_on_hold_id_unique"

    # ---- Enum-ish columns, readable in psql during an incident ----------------
    add_check_constraint :buses, "bus_type IN ('ac','non_ac')", name: "buses_bus_type_valid"
    add_check_constraint :buses, "berth_type IN ('sleeper','seater')", name: "buses_berth_type_valid"
    add_check_constraint :trips, "status IN ('scheduled','departed','cancelled')", name: "trips_status_valid"
    add_check_constraint :trip_stops, "type IN ('BoardingStop','DroppingStop')", name: "trip_stops_type_valid"
    add_check_constraint :trip_seats, "status IN ('available','held','booked','blocked')", name: "trip_seats_status_valid"
    add_check_constraint :holds, "status IN ('active','converted','released','expired')", name: "holds_status_valid"
    add_check_constraint :bookings, "status IN ('confirmed','cancelled','rescheduled')", name: "bookings_status_valid"

    # ---- Invariants the domain depends on -------------------------------------
    add_check_constraint :trips, "arrives_at > departs_at", name: "trips_arrive_after_departure"
    add_check_constraint :trips, "seats_available BETWEEN 0 AND seats_total", name: "trips_seats_available_in_range"
    add_check_constraint :holds, "expires_at > created_at", name: "holds_expire_after_creation"
    add_check_constraint :operators, "rating BETWEEN 0 AND 5", name: "operators_rating_in_range"

    # A held seat must say which hold holds it and until when, or `claimable?`
    # cannot decide anything inside the lock.
    add_check_constraint :trip_seats,
                         "status <> 'held' OR (hold_id IS NOT NULL AND hold_expires_at IS NOT NULL)",
                         name: "trip_seats_held_has_a_hold"

    # A cancelled booking has a cancellation time and a refund figure.
    add_check_constraint :bookings,
                         "status <> 'cancelled' OR (cancelled_at IS NOT NULL AND refund_paise IS NOT NULL)",
                         name: "bookings_cancelled_has_refund"

    # ---- Money is never negative ----------------------------------------------
    add_check_constraint :trips, "base_fare_paise >= 0", name: "trips_fare_non_negative"
    add_check_constraint :trip_seats, "price_paise >= 0", name: "trip_seats_price_non_negative"
    add_check_constraint :holds, "total_paise >= 0", name: "holds_total_non_negative"
    add_check_constraint :bookings, "total_paise >= 0", name: "bookings_total_non_negative"
    add_check_constraint :bookings, "refund_paise IS NULL OR refund_paise >= 0", name: "bookings_refund_non_negative"
    add_check_constraint :tickets, "price_paise >= 0", name: "tickets_price_non_negative"
  end
end
