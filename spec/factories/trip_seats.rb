FactoryBot.define do
  factory :trip_seat do
    trip
    sequence(:seat_number) { |n| "#{n}A" }
    status { "available" }
    berth_type { "seater" }
    price_paise { 90_000 }
  end
end
