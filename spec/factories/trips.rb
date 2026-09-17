FactoryBot.define do
  factory :trip do
    operator { nil }
    bus { nil }
    origin_city { nil }
    destination_city { nil }
    departs_at { "2026-09-17 11:54:13" }
    arrives_at { "2026-09-17 11:54:13" }
    base_fare_paise { 1 }
    status { "MyString" }
    seats_available { 1 }
  end
end
