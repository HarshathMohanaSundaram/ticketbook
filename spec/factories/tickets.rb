FactoryBot.define do
  factory :ticket do
    booking
    trip_seat
    passenger_name { "Ravi Kumar" }
    passenger_age { 34 }
    gender { "male" }
    price_paise { 90_000 }
  end
end
