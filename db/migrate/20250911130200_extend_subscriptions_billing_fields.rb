class ExtendSubscriptionsBillingFields < ActiveRecord::Migration[8.0]
  def change
    add_column :subscriptions, :cancel_at_period_end, :boolean, default: false, null: false
    add_column :subscriptions, :current_period_start, :datetime
  end
end

