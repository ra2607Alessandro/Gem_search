FactoryBot.define do
  factory :search_result do
    search { nil }
    document { nil }
    relevance_score { 1.5 }
  end
end
