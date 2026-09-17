FactoryBot.define do
  factory :booking do
    user { nil }
    trip { nil }
    hold { nil }
    boarding_stop { nil }
    dropping_stop { nil }
    rescheduled_from { nil }
    pnr { "MyString" }
    status { "MyString" }
    total_paise { 1 }
    departs_at { "2026-09-17 11:54:58" }
    cancelled_at { "2026-09-17 11:54:58" }
    refund_paise { 1 }
  end
end
