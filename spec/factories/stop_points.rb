FactoryBot.define do
  factory :stop_point do
    city
    sequence(:name) { |n| "Stop Point #{n}" }
    landmark { "Near the flyover" }
  end
end
