FactoryBot.define do
  factory :ticket do
    booking { nil }
    trip_seat { nil }
    passenger_name { "MyString" }
    passenger_age { 1 }
    gender { "MyString" }
    price_paise { 1 }
  end
end
