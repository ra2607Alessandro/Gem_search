class RateLimiter
  def self.enforce!(current_user: nil, ip:)
    plan = current_user ? current_user.current_plan : Plan.default
    limit = plan.daily_search_limit.to_i

    search_scope = if current_user
                     Search.where(user_id: current_user.id)
                   else
                     Search.where(user_ip: ip)
                   end

    count = search_scope.where('created_at >= ?', Time.current.beginning_of_day).count
    count < limit
  end
end
