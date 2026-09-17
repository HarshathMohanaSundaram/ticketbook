FactoryBot.define do
  factory :trip_stop do
    trip
    stop_point
    scheduled_at { 1.day.from_now }
    position { 0 }

    factory :boarding_stop, class: "BoardingStop"
    factory :dropping_stop, class: "DroppingStop"
  end
end
