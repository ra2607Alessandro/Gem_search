module Billing
  class CheckoutService
    def initialize(user)
      @user = user
    end

    def create_checkout_session
      ensure_customer!

      price_id = ENV['STRIPE_PRICE_ID_PRO_MONTHLY']
      raise 'Missing STRIPE_PRICE_ID_PRO_MONTHLY' if price_id.blank?

      success_url = build_url('/billing/confirm?session_id={CHECKOUT_SESSION_ID}')
      cancel_url  = build_url('/pricing?canceled=1')

      Stripe::Checkout::Session.create(
        mode: 'subscription',
        customer: @user.stripe_customer_id,
        line_items: [
          { price: price_id, quantity: 1 }
        ],
        success_url: success_url,
        cancel_url: cancel_url,
        client_reference_id: @user.id.to_s
      )
    end

    private

    def ensure_customer!
      return if @user.stripe_customer_id.present?
      customer = Stripe::Customer.create(email: @user.email, metadata: { user_id: @user.id })
      @user.update!(stripe_customer_id: customer.id)
    end

    def build_url(path)
      base = ENV['APP_BASE_URL'] || Rails.application.routes.default_url_options[:host] || 'http://localhost:3000'
      URI.join(base, path).to_s
    end
  end
end
