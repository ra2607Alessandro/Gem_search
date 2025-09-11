# Simple monthly quota enforcement for authenticated users
class RateLimiter
  Result = Struct.new(:allowed, :remaining, :limit, keyword_init: true)

  def self.enforce!(current_user:, ip: nil)
    return true unless current_user

    result = Usage::MonthlyQuotaChecker.new(current_user).call
    result.allowed
  rescue => e
    Rails.logger.error("[RateLimiter] Error checking quota: #{e.message}")
    true
  end
end

