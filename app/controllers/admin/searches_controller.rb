# frozen_string_literal: true

module Admin
    # This controller provides a simple dashboard to monitor the status of searches.
    class SearchesController < ApplicationController
      # Simple auth to protect the dashboard. In a real app, use a proper auth system.
      http_basic_authenticate_with name: Rails.application.credentials.dig(:admin, :username),
                                   password: Rails.application.credentials.dig(:admin, :password)
  
      def index
        @searches = Search.order(created_at: :desc).limit(100)
        @job_counts = {
          total: SolidQueue::Job.count,
          pending: SolidQueue::ReadyJob.count,
          in_progress: SolidQueue::ClaimedJob.count,
          failed: SolidQueue::FailedExecution.count
        }
      end
    end
  end