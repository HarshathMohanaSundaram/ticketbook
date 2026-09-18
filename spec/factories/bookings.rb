FactoryBot.define do
  factory :booking do
    user
    trip
    pnr { Booking.generate_pnr }
    status { "confirmed" }
    total_paise { 120_000 }
    departs_at { trip.departs_at }

    # A booking with real seats and tickets behind it, as the confirmation
    # service would leave things.
    trait :with_seats do
      transient { seat_count { 1 } }

      after(:create) do |booking, evaluator|
        evaluator.seat_count.times do |i|
          seat = create(:trip_seat, trip: booking.trip, seat_number: "B#{i + 1}",
                                    status: "booked", price_paise: booking.total_paise / evaluator.seat_count)
          create(:ticket, booking: booking, trip_seat: seat, price_paise: seat.price_paise)
        end
      end
    end
  end
end
