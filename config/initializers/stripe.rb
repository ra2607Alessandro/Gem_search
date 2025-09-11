if defined?(Stripe)
  Stripe.api_key = ENV['STRIPE_SECRET_KEY']
  # Optionally, set an app info for logs
  Stripe.set_app_info('GemSearch', version: '1.0.0') rescue nil

  if Rails.env.development? || Rails.env.test?
    missing = %w[STRIPE_SECRET_KEY STRIPE_PUBLISHABLE_KEY STRIPE_PRICE_ID_PRO_MONTHLY].reject { |k| ENV[k].present? }
    Rails.logger.warn("[Stripe] Missing env vars: #{missing.join(', ')}") if missing.any?
  end
end

