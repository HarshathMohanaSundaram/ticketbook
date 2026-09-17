FactoryBot.define do
  factory :bus do
    operator { nil }
    registration_number { "MyString" }
    bus_type { "MyString" }
    berth_type { "MyString" }
    seats_total { 1 }
  end
end
