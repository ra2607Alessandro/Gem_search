# frozen_string_literal: true

module Admin
    module SearchesHelper
      # Returns a Tailwind CSS class for a status badge based on the search status.
      def status_badge_class(status)
        case status
        when 'completed'
          'bg-green-100 text-green-800'
        when 'failed'
          'bg-red-100 text-red-800'
        when 'scraping'
          'bg-yellow-100 text-yellow-800'
        when 'processing'
          'bg-blue-100 text-blue-800'
        else
          'bg-gray-100 text-gray-800'
        end
      end
    end
  end