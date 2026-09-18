FactoryBot.define do
  factory :hold do
    user
    trip
    expires_at { Hold::HOLD_WINDOW.from_now }
    status { "active" }
    total_paise { 90_000 }
  end
end
