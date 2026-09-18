FactoryBot.define do
  factory :driver do
    operator
    name { "Ramesh Kumar" }
    phone { "9876543210" }
    sequence(:licence_number) { |n| "KA0#{n}#{rand(10_000..99_999)}" }
    licence_expires_on { 1.year.from_now.to_date }
  end
end
