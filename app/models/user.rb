class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :subscriptions, dependent: :destroy
  has_many :plans, through: :subscriptions
  has_many :searches, dependent: :nullify

  def current_plan
    # Prefer active subscription if present, otherwise fall back to most recent plan
    active = subscriptions.where(status: 'active').includes(:plan).order(created_at: :desc).first
    plan = active&.plan || subscriptions.includes(:plan).order(created_at: :desc).first&.plan
    plan || Plan.default
  end

  # Monthly quotas
  def monthly_search_quota
    # nil means unlimited
    current_plan&.monthly_search_limit
  end

  def monthly_searches_used
    searches.where('created_at >= ?', Time.current.beginning_of_month).count
  end

  def remaining_monthly_searches
    return nil if monthly_search_quota.nil?
    [monthly_search_quota.to_i - monthly_searches_used, 0].max
  end

  # Backward-compatible names used by existing views
  def search_quota
    monthly_search_quota
  end

  def remaining_searches
    remaining_monthly_searches || Float::INFINITY
  end
end


