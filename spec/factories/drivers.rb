FactoryBot.define do
  factory :driver do
    operator { nil }
    name { "MyString" }
    phone { "MyString" }
    licence_number { "MyString" }
    licence_expires_on { "2026-09-17" }
  end
end
