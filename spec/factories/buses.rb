FactoryBot.define do
  factory :bus do
    operator
    sequence(:registration_number) { |n| "KA01AB#{1000 + n}" }
    bus_type { "ac" }
    berth_type { "seater" }
    seats_total { 4 }
    amenity_codes { %w[wifi] }
  end
end
