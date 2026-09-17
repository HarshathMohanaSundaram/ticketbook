FactoryBot.define do
  factory :trip_seat do
    trip { nil }
    hold { nil }
    seat_number { "MyString" }
    status { "MyString" }
    berth_type { "MyString" }
    price_paise { 1 }
    hold_expires_at { "2026-09-17 11:54:59" }
  end
end
