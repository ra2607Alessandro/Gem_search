module Billing
  class StripeSyncService
    def initialize(event)
      @event = event
      @type  = event['type']
      @data  = event['data'] && event['data']['object']
    end

    def call
      case @type
      when 'checkout.session.completed'
        handle_checkout_session_completed
      when 'customer.subscription.created', 'customer.subscription.updated', 'customer.subscription.deleted'
        handle_subscription_changed
      when 'invoice.payment_succeeded', 'invoice.payment_failed'
        # Optional: could log or mark invoices, not required for quota
        true
      else
        true
      end
    end

    private

    def handle_checkout_session_completed
      session = @data
      user = find_user_from_session(session)
      return true unless user

      if user.stripe_customer_id.blank? && session['customer'].present?
        user.update!(stripe_customer_id: session['customer'])
      end

      # Attach or create subscription record
      sub_id = session['subscription']
      return true if sub_id.blank?

      sync_subscription_for(user, sub_id)
    end

    def handle_subscription_changed
      sub = @data
      sub_id = sub['id']
      customer_id = sub['customer']
      user = User.find_by(stripe_customer_id: customer_id)
      return true unless user

      status = sub['status']
      current_period_start = Time.at(sub['current_period_start']).utc rescue nil
      current_period_end = Time.at(sub['current_period_end']).utc rescue nil
      cancel_at_period_end = !!sub['cancel_at_period_end']

      plan = Plan.find_by(name: 'Pro') || Plan.default

      record = user.subscriptions.where(billing_id: sub_id).first_or_initialize(plan: plan)
      record.update!(
        status: status,
        current_period_start: current_period_start,
        current_period_end: current_period_end,
        cancel_at_period_end: cancel_at_period_end
      )
    end

    def sync_subscription_for(user, sub_id)
      subscription = Stripe::Subscription.retrieve(sub_id)
      status = subscription['status']
      current_period_start = Time.at(subscription['current_period_start']).utc rescue nil
      current_period_end = Time.at(subscription['current_period_end']).utc rescue nil
      cancel_at_period_end = !!subscription['cancel_at_period_end']

      plan = Plan.find_by(name: 'Pro') || Plan.default
      record = user.subscriptions.where(billing_id: sub_id).first_or_initialize(plan: plan)
      record.update!(
        status: status,
        current_period_start: current_period_start,
        current_period_end: current_period_end,
        cancel_at_period_end: cancel_at_period_end
      )
    end

    def find_user_from_session(session)
      if session['client_reference_id'].present?
        User.find_by(id: session['client_reference_id'])
      elsif session['customer'].present?
        User.find_by(stripe_customer_id: session['customer'])
      else
        nil
      end
    end
  end
end

