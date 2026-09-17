# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_09_17_071641) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "plpgsql"

  create_table "bookings", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "trip_id", null: false
    t.bigint "hold_id"
    t.bigint "boarding_stop_id"
    t.bigint "dropping_stop_id"
    t.bigint "rescheduled_from_id"
    t.string "pnr", null: false
    t.string "status", default: "confirmed", null: false
    t.integer "total_paise", null: false
    t.datetime "departs_at", null: false
    t.datetime "cancelled_at"
    t.integer "refund_paise"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["boarding_stop_id"], name: "index_bookings_on_boarding_stop_id"
    t.index ["dropping_stop_id"], name: "index_bookings_on_dropping_stop_id"
    t.index ["hold_id"], name: "index_bookings_on_hold_id"
    t.index ["hold_id"], name: "index_bookings_on_hold_id_unique", unique: true, where: "(hold_id IS NOT NULL)"
    t.index ["pnr"], name: "index_bookings_on_pnr", unique: true
    t.index ["rescheduled_from_id"], name: "index_bookings_on_rescheduled_from_id"
    t.index ["trip_id"], name: "index_bookings_on_trip_id"
    t.index ["user_id", "created_at"], name: "index_bookings_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_bookings_on_user_id"
    t.check_constraint "refund_paise IS NULL OR refund_paise >= 0", name: "bookings_refund_non_negative"
    t.check_constraint "status::text <> 'cancelled'::text OR cancelled_at IS NOT NULL AND refund_paise IS NOT NULL", name: "bookings_cancelled_has_refund"
    t.check_constraint "status::text = ANY (ARRAY['confirmed'::character varying, 'cancelled'::character varying, 'rescheduled'::character varying]::text[])", name: "bookings_status_valid"
    t.check_constraint "total_paise >= 0", name: "bookings_total_non_negative"
  end

  create_table "buses", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.string "registration_number", null: false
    t.string "bus_type", null: false
    t.string "berth_type", null: false
    t.integer "seats_total", default: 0, null: false
    t.string "amenity_codes", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["amenity_codes"], name: "index_buses_on_amenity_codes", using: :gin
    t.index ["bus_type", "berth_type"], name: "index_buses_on_bus_type_and_berth_type"
    t.index ["operator_id"], name: "index_buses_on_operator_id"
    t.index ["registration_number"], name: "index_buses_on_registration_number", unique: true
    t.check_constraint "berth_type::text = ANY (ARRAY['sleeper'::character varying, 'seater'::character varying]::text[])", name: "buses_berth_type_valid"
    t.check_constraint "bus_type::text = ANY (ARRAY['ac'::character varying, 'non_ac'::character varying]::text[])", name: "buses_bus_type_valid"
  end

  create_table "cities", force: :cascade do |t|
    t.string "name", null: false
    t.string "state", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_cities_on_slug", unique: true
  end

  create_table "drivers", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.string "name", null: false
    t.string "phone"
    t.string "licence_number", null: false
    t.date "licence_expires_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["licence_number"], name: "index_drivers_on_licence_number", unique: true
    t.index ["operator_id"], name: "index_drivers_on_operator_id"
  end

  create_table "holds", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "trip_id", null: false
    t.datetime "expires_at", null: false
    t.string "status", default: "active", null: false
    t.integer "total_paise", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status", "expires_at"], name: "index_holds_on_status_and_expires_at"
    t.index ["trip_id"], name: "index_holds_on_trip_id"
    t.index ["user_id"], name: "index_holds_on_user_id"
    t.check_constraint "expires_at > created_at", name: "holds_expire_after_creation"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'converted'::character varying, 'released'::character varying, 'expired'::character varying]::text[])", name: "holds_status_valid"
    t.check_constraint "total_paise >= 0", name: "holds_total_non_negative"
  end

  create_table "operators", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.decimal "rating", precision: 2, scale: 1, default: "0.0", null: false
    t.integer "ratings_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["rating"], name: "index_operators_on_rating"
    t.index ["slug"], name: "index_operators_on_slug", unique: true
    t.check_constraint "rating >= 0::numeric AND rating <= 5::numeric", name: "operators_rating_in_range"
  end

  create_table "stop_points", force: :cascade do |t|
    t.bigint "city_id", null: false
    t.bigint "operator_id"
    t.string "name", null: false
    t.string "landmark"
    t.string "address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["city_id"], name: "index_stop_points_on_city_id"
    t.index ["operator_id"], name: "index_stop_points_on_operator_id"
  end

  create_table "tickets", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.bigint "trip_seat_id", null: false
    t.string "passenger_name", null: false
    t.integer "passenger_age"
    t.string "gender"
    t.integer "price_paise", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id", "trip_seat_id"], name: "index_tickets_on_booking_id_and_trip_seat_id", unique: true
    t.index ["booking_id"], name: "index_tickets_on_booking_id"
    t.index ["trip_seat_id"], name: "index_tickets_on_trip_seat_id"
    t.check_constraint "price_paise >= 0", name: "tickets_price_non_negative"
  end

  create_table "trip_seats", force: :cascade do |t|
    t.bigint "trip_id", null: false
    t.bigint "hold_id"
    t.string "seat_number", null: false
    t.string "status", default: "available", null: false
    t.string "berth_type", null: false
    t.integer "price_paise", null: false
    t.datetime "hold_expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hold_id"], name: "index_trip_seats_on_active_hold", where: "(hold_id IS NOT NULL)"
    t.index ["hold_id"], name: "index_trip_seats_on_hold_id"
    t.index ["trip_id", "seat_number"], name: "index_trip_seats_on_trip_id_and_seat_number", unique: true
    t.index ["trip_id", "status"], name: "index_trip_seats_on_trip_id_and_status"
    t.index ["trip_id"], name: "index_trip_seats_on_trip_id"
    t.check_constraint "price_paise >= 0", name: "trip_seats_price_non_negative"
    t.check_constraint "status::text <> 'held'::text OR hold_id IS NOT NULL AND hold_expires_at IS NOT NULL", name: "trip_seats_held_has_a_hold"
    t.check_constraint "status::text = ANY (ARRAY['available'::character varying, 'held'::character varying, 'booked'::character varying, 'blocked'::character varying]::text[])", name: "trip_seats_status_valid"
  end

  create_table "trip_stops", force: :cascade do |t|
    t.bigint "trip_id", null: false
    t.bigint "stop_point_id", null: false
    t.string "type", null: false
    t.datetime "scheduled_at", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stop_point_id"], name: "index_trip_stops_on_stop_point_id"
    t.index ["trip_id", "stop_point_id", "type"], name: "index_trip_stops_on_trip_and_point_and_type", unique: true
    t.index ["trip_id", "type", "position"], name: "index_trip_stops_on_trip_id_and_type_and_position"
    t.index ["trip_id"], name: "index_trip_stops_on_trip_id"
    t.check_constraint "type::text = ANY (ARRAY['BoardingStop'::character varying, 'DroppingStop'::character varying]::text[])", name: "trip_stops_type_valid"
  end

  create_table "trips", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.bigint "bus_id", null: false
    t.bigint "origin_city_id", null: false
    t.bigint "destination_city_id", null: false
    t.datetime "departs_at", null: false
    t.datetime "arrives_at", null: false
    t.integer "base_fare_paise", null: false
    t.string "status", default: "scheduled", null: false
    t.integer "seats_total", default: 0, null: false
    t.integer "seats_available", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "driver_id"
    t.bigint "relief_driver_id"
    t.index ["bus_id"], name: "index_trips_on_bus_id"
    t.index ["departs_at"], name: "index_trips_on_departs_at"
    t.index ["destination_city_id"], name: "index_trips_on_destination_city_id"
    t.index ["driver_id"], name: "index_trips_on_driver_id"
    t.index ["operator_id", "departs_at"], name: "index_trips_on_operator_id_and_departs_at"
    t.index ["operator_id"], name: "index_trips_on_operator_id"
    t.index ["origin_city_id", "destination_city_id", "departs_at"], name: "index_trips_on_search_triple"
    t.index ["origin_city_id"], name: "index_trips_on_origin_city_id"
    t.index ["relief_driver_id"], name: "index_trips_on_relief_driver_id"
    t.check_constraint "arrives_at > departs_at", name: "trips_arrive_after_departure"
    t.check_constraint "base_fare_paise >= 0", name: "trips_fare_non_negative"
    t.check_constraint "relief_driver_id IS NULL OR relief_driver_id <> driver_id", name: "trips_relief_driver_differs"
    t.check_constraint "seats_available >= 0 AND seats_available <= seats_total", name: "trips_seats_available_in_range"
    t.check_constraint "status::text = ANY (ARRAY['scheduled'::character varying, 'departed'::character varying, 'cancelled'::character varying]::text[])", name: "trips_status_valid"
  end

  create_table "users", force: :cascade do |t|
    t.citext "email", null: false
    t.string "name"
    t.string "phone"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "bookings", "bookings", column: "rescheduled_from_id"
  add_foreign_key "bookings", "holds"
  add_foreign_key "bookings", "trip_stops", column: "boarding_stop_id"
  add_foreign_key "bookings", "trip_stops", column: "dropping_stop_id"
  add_foreign_key "bookings", "trips"
  add_foreign_key "bookings", "users"
  add_foreign_key "buses", "operators"
  add_foreign_key "drivers", "operators"
  add_foreign_key "holds", "trips"
  add_foreign_key "holds", "users"
  add_foreign_key "stop_points", "cities"
  add_foreign_key "stop_points", "operators"
  add_foreign_key "tickets", "bookings"
  add_foreign_key "tickets", "trip_seats"
  add_foreign_key "trip_seats", "holds"
  add_foreign_key "trip_seats", "trips"
  add_foreign_key "trip_stops", "stop_points"
  add_foreign_key "trip_stops", "trips"
  add_foreign_key "trips", "buses"
  add_foreign_key "trips", "cities", column: "destination_city_id"
  add_foreign_key "trips", "cities", column: "origin_city_id"
  add_foreign_key "trips", "drivers"
  add_foreign_key "trips", "drivers", column: "relief_driver_id"
  add_foreign_key "trips", "operators"
end
