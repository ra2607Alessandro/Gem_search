class Subscription < ApplicationRecord
  belongs_to :user
  belongs_to :plan

  scope :active, -> { where(status: 'active') }
  scope :latest_first, -> { order(created_at: :desc) }

  def active?
    status == 'active'
  end
end
