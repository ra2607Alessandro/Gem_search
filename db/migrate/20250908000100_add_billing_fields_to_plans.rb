class AddBillingFieldsToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :price_cents, :integer, default: 0
    add_column :plans, :interval, :string
  end
end
