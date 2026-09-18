FactoryBot.define do
  factory :operator do
    sequence(:name) { |n| "Operator #{n}" }
    sequence(:slug) { |n| "operator-#{n}" }
    rating { 4.0 }
    ratings_count { 100 }
  end
end
