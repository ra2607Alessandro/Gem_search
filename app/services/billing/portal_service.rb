module Billing
  class PortalService
    def initialize(user)
      @user = user
    end

    def create_portal_session
      raise 'No Stripe customer for user' if @user.stripe_customer_id.blank?
      return_url = build_url('/pricing')
      Stripe::BillingPortal::Session.create(customer: @user.stripe_customer_id, return_url: return_url)
    end

    private

    def build_url(path)
      base = ENV['APP_BASE_URL'] || Rails.application.routes.default_url_options[:host] || 'http://localhost:3000'
      URI.join(base, path).to_s
    end
  end
end

