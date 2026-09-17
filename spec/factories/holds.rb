FactoryBot.define do
  factory :hold do
    user { nil }
    trip { nil }
    expires_at { "2026-09-17 11:54:58" }
    status { "MyString" }
    total_paise { 1 }
  end
end
