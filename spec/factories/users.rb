FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "passenger#{n}@example.com" }
    name { "Test Passenger" }
  end
end
