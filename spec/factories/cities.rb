FactoryBot.define do
  factory :city do
    sequence(:name) { |n| "City #{n}" }
    state { "Karnataka" }
    sequence(:slug) { |n| "city-#{n}" }
  end
end
