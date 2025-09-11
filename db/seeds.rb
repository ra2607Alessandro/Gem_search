# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Pricing plans
if defined?(Plan)
  free = Plan.find_or_create_by!(name: 'Free') do |p|
    p.price_cents = 0
    p.interval = 'none'
  end
  free.update!(monthly_search_limit: (ENV['FREE_MONTHLY_SEARCH_LIMIT'] || 20).to_i)

  pro = Plan.find_or_create_by!(name: 'Pro') do |p|
    p.interval = 'month'
  end
  pro.update!(
    monthly_search_limit: nil, # unlimited
    price_cents: (ENV['PRO_PRICE_CENTS'] || 899).to_i,
    stripe_price_id: ENV['STRIPE_PRICE_ID_PRO_MONTHLY']
  )
end
