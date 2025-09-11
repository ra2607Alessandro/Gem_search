module Usage
  class MonthlyQuotaChecker
    Result = Struct.new(:allowed, :remaining, :limit, keyword_init: true)

    def initialize(user)
      @user = user
    end

    def call
      limit = @user.monthly_search_quota
      return Result.new(allowed: true, remaining: nil, limit: nil) if limit.nil?

      used = @user.monthly_searches_used
      remaining = [limit.to_i - used, 0].max
      Result.new(allowed: remaining > 0, remaining: remaining, limit: limit.to_i)
    end
  end
end

