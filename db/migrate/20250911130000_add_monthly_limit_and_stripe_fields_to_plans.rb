class AddMonthlyLimitAndStripeFieldsToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :monthly_search_limit, :integer
    add_column :plans, :stripe_price_id, :string
    add_column :plans, :stripe_product_id, :string
  end
end

