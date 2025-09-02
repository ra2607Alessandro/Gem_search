FactoryBot.define do
  factory :search do
    query { "MyText" }
    goal { "MyText" }
    rules { "MyText" }
    user_ip { "MyString" }
    status { 1 }
  end
end
