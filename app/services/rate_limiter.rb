class RateLimiter
  def self.enforce!(current_user: nil, ip:)
    plan = if current_user&.respond_to?(:plan) && current_user.plan
             current_user.plan
           else
             Plan.default
           end

    limit = plan.daily_search_limit

    search_scope = if current_user&.respond_to?(:searches)
                     current_user.searches
                   else
                     Search.where(user_ip: ip)
                   end

    count = search_scope.where('created_at >= ?', Time.current.beginning_of_day).count
    count < limit
  end
end
