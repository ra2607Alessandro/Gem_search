class Plan < ApplicationRecord

  DEFAULT_DAILY_SEARCH_LIMIT = 100

  def self.default
    first || new(daily_search_limit: DEFAULT_DAILY_SEARCH_LIMIT)
  end

  has_many :subscriptions, dependent: :destroy
  has_many :users, through: :subscriptions

  validates :name, presence: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :interval, presence: true

end
