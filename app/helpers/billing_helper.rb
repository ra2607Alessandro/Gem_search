module BillingHelper
  def format_price_cents(cents)
    return '$0' if cents.nil? || cents.to_i.zero?
    format('$%.2f', cents.to_i / 100.0)
  end

  def quota_label_for(plan)
    if plan&.monthly_search_limit.nil?
      'Unlimited searches per month'
    else
      "#{plan.monthly_search_limit} searches per month"
    end
  end

  def remaining_label_for(user)
    quota = user.monthly_search_quota
    if quota.nil?
      'Unlimited'
    else
      "#{user.remaining_monthly_searches} of #{quota}"
    end
  end
end

