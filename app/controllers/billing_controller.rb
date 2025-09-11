class BillingController < ApplicationController
  before_action :authenticate_user!, only: [:create_checkout_session, :portal, :confirm]
  skip_before_action :verify_authenticity_token, only: [:webhook, :callback]

  # Legacy no-op to maintain compatibility if configured
  def callback
    head :ok
  end

  def create_checkout_session
    service = Billing::CheckoutService.new(current_user)
    session = service.create_checkout_session
    respond_to do |format|
      format.html { redirect_to session.url, allow_other_host: true, status: :see_other }
      format.json { render json: { id: session.id, url: session.url } }
    end
  rescue => e
    Rails.logger.error("[Billing] Checkout error: #{e.message}")
    redirect_to pricing_path, alert: 'Unable to start checkout.'
  end

  def portal
    service = Billing::PortalService.new(current_user)
    session = service.create_portal_session
    redirect_to session.url, allow_other_host: true, status: :see_other
  rescue => e
    Rails.logger.error("[Billing] Portal error: #{e.message}")
    redirect_to pricing_path, alert: 'Unable to open billing portal.'
  end

  def webhook
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    secret = ENV['STRIPE_WEBHOOK_SECRET']

    event = if secret.present?
      Stripe::Webhook.construct_event(payload, sig_header, secret)
    else
      # In development, accept unsigned payloads (not recommended for prod)
      JSON.parse(payload)
    end

    Billing::StripeSyncService.new(event).call
    head :ok
  rescue JSON::ParserError => e
    Rails.logger.error("[Billing] Webhook JSON error: #{e.message}")
    head :bad_request
  rescue Stripe::SignatureVerificationError => e
    Rails.logger.error("[Billing] Signature verification failed: #{e.message}")
    head :bad_request
  rescue => e
    Rails.logger.error("[Billing] Webhook error: #{e.message}")
    head :ok
  end

  # Instant confirmation path after Stripe redirects back with the session id.
  # This mirrors the webhook's effect so the UI updates immediately even if webhooks lag.
  def confirm
    session_id = params[:session_id]
    unless session_id.present?
      redirect_to pricing_path, alert: 'Missing checkout session.' and return
    end

    session = Stripe::Checkout::Session.retrieve(session_id)

    # Security: ensure this session belongs to the current user
    client_ref_id = session['client_reference_id']
    customer_id = session['customer']
    if client_ref_id.present? && client_ref_id.to_s != current_user.id.to_s
      redirect_to pricing_path, alert: 'This session does not belong to you.' and return
    end
    if client_ref_id.blank? && current_user.stripe_customer_id.present? && customer_id.present? && customer_id != current_user.stripe_customer_id
      redirect_to pricing_path, alert: 'This session does not belong to you.' and return
    end

    session_payload = session.respond_to?(:to_hash) ? session.to_hash : JSON.parse(session.to_json)
    event_like = {
      'type' => 'checkout.session.completed',
      'data' => { 'object' => session_payload }
    }
    Billing::StripeSyncService.new(event_like).call

    redirect_to pricing_path(upgraded: 1), notice: 'Subscription updated.'
  rescue => e
    Rails.logger.error("[Billing] Confirm error: #{e.message}")
    redirect_to pricing_path, alert: 'Could not confirm subscription.'
  end
end
