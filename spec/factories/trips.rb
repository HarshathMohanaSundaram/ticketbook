FactoryBot.define do
  factory :trip do
    operator
    bus { association :bus, operator: operator }
    origin_city { association :city }
    destination_city { association :city }
    departs_at { 2.days.from_now.change(hour: 21) }
    arrives_at { departs_at + 6.hours }
    base_fare_paise { 90_000 }
    status { "scheduled" }
    seats_total { 4 }

    # Materialises the seats, as TripPublishing would in the real flow.
    trait :with_seats do
      transient { seat_count { 4 } }

      after(:create) do |trip, evaluator|
        evaluator.seat_count.times do |i|
          create(:trip_seat, trip: trip, seat_number: "#{i + 1}A",
                             price_paise: trip.base_fare_paise)
        end
        trip.update!(seats_total: evaluator.seat_count)
      end
    end

    trait :with_stops do
      after(:create) do |trip|
        create(:boarding_stop, trip: trip, scheduled_at: trip.departs_at)
        create(:dropping_stop, trip: trip, scheduled_at: trip.arrives_at)
      end
    end
  end
end
