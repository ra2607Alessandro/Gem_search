class AddStripeCustomerIdToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :stripe_customer_id, :string
    add_index :users, :stripe_customer_id, unique: true, where: "stripe_customer_id IS NOT NULL"
  end
end

