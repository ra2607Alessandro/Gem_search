class BillingController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :callback

  def callback
    # Handle webhook callbacks from billing provider
    head :ok
  end
end
