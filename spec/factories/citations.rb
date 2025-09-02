FactoryBot.define do
  factory :citation do
    search_result { nil }
    source_url { "MyText" }
    snippet { "MyText" }
  end
end
