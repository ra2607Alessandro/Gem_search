class BackfillPlanLimitsAndPrices < ActiveRecord::Migration[8.0]
  def up
    free = Plan.find_by(name: 'Free')
    free&.update_columns(monthly_search_limit: 20, price_cents: 0, interval: 'none')

    pro = Plan.find_by(name: 'Pro')
    pro&.update_columns(monthly_search_limit: nil, price_cents: 899, interval: 'month')
  end

  def down
    # no-op: do not revert pricing
  end
end

