class SearchesController < ApplicationController
  before_action :find_search, only: [:show]
  before_action :authorize_search, only: [:show]

  # Include ActionController::Live for streaming responses
  include ActionController::Live

  # Simple SSE (Server-Sent Events) implementation
  class SSE
    def initialize(stream, options = {})
      @stream = stream
      @retry = options[:retry] || 3000
    end

    def write(data)
      @stream.write "data: #{data.to_json}\n\n"
    end

    def close
      @stream.close
    end
  end

  def index
    @searches = Search.includes(:search_results)
                      .order(created_at: :desc)
                      .limit(50)

    @search_stats = calculate_search_stats
  end

  def create
    @search = Search.new(search_params)
    @search.user_ip = request.remote_ip

    if @search.save
      # The SearchProcessingJob will be triggered by the after_create callback
      # in the Search model

      respond_to do |format|
        format.html { redirect_to @search }
        format.turbo_stream
      end
    else
      respond_to do |format|
        format.html do
          @searches = Search.order(created_at: :desc).limit(50)
          @search_stats = calculate_search_stats
          render :index, status: :unprocessable_entity
        end
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            'search_form',
            partial: 'searches/form',
            locals: { search: @search }
          ), status: :unprocessable_entity
        end
      end
    end
  end

  def show
    @search_results = @search.search_results
                              .includes(:document)
                              .ordered_by_relevance

    # Prepare data for potential AI response (will be implemented later)
    prepare_ai_response_data if @search.completed?

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def retry_ai_generation
    @search = Search.find(params[:id])
    
    if @search.scraping? || @search.failed?
      documents_with_content = @search.documents.where.not(content: [nil, ''])
      content_count = documents_with_content.count
    
      if content_count >= Ai::ResponseGenerationService::MIN_SOURCES_REQUIRED
        Rails.logger.info "Manual retry triggered for search #{@search.id}. Found #{content_count} documents with content."
        @search.update(status: :scraping, updated_at: Time.current)
        AiResponseGenerationJob.perform_later(@search.id)
        redirect_to @search, notice: 'AI response generation has been manually triggered. The page will update shortly.'
      elsif content_count > 0
        redirect_to @search, alert: "Cannot generate AI response: Need at least #{Ai::ResponseGenerationService::MIN_SOURCES_REQUIRED} sources with content, but only #{content_count} available."
      else
        redirect_to @search, alert: 'Cannot generate AI response: No content has been successfully scraped.'
      end
    else
      redirect_to @search, alert: "AI response can only be retried for 'scraping' or 'failed' searches."
    end
  end

  private

  def search_params
    params.require(:search).permit(:query, :goal, :rules)
  end

  def find_search
    @search = Search.includes(search_results: [:document, :citations]).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to searches_path, alert: 'Search not found.'
  end

  def authorize_search
    # For now, allow access to all searches
    # In production, you might want to restrict by IP or session
    return true

    # More restrictive authorization (uncomment when needed):
    # unless @search.user_ip == request.remote_ip
    #   redirect_to searches_path, alert: 'You can only view your own searches.'
    # end
  end

  def calculate_search_stats
    total_searches = Search.count
    completed_searches = Search.where(status: :completed).count
    processing_searches = Search.where(status: :processing).count
    failed_searches = Search.where(status: :failed).count

    recent_searches = Search.where('created_at >= ?', 24.hours.ago)
    searches_last_24h = recent_searches.count

    {
      total: total_searches,
      completed: completed_searches,
      processing: processing_searches,
      failed: failed_searches,
      last_24h: searches_last_24h,

      completion_rate: total_searches > 0 ? (completed_searches.to_f / total_searches * 100).round(1) : 0    }
  end

  def prepare_ai_response_data
    @ai_response_data = {
      search_results: @search_results,
      total_sources: @search_results.count,
      top_sources: @search_results.limit(5),
      response: @search.ai_response,
      follow_up_questions: @search.follow_up_questions
    }
  end

  # Turbo Stream methods for real-time updates
  def stream_search_status
    search = Search.find(params[:id])
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'

    sse = SSE.new(response.stream, retry: 300)

    begin
      # Send initial status
      sse.write({ status: search.status, progress: calculate_progress(search) })

      # Keep connection alive and send updates
      while search.processing?
        sleep 2 # Check every 2 seconds
        search.reload

        progress_data = {
          status: search.status,
          progress: calculate_progress(search),
          sources_found: search.search_results.count
        }

        sse.write(progress_data)

        # Break if search is completed or failed
        break unless search.processing?
      end

      # Send final status
      sse.write({
        status: search.status,
        progress: 100,
        sources_found: search.search_results.count,
        completed: true
      })

    rescue IOError
      # Client disconnected
    ensure
      sse.close
    end
  end

  private

  def calculate_progress(search)
    case search.status.to_sym
    when :pending
      0
    when :processing
      # Estimate progress based on sources found
      sources_found = search.search_results.count
      max_sources = 10 # Expected maximum
      [(sources_found * 80 / max_sources.to_f).round, 80].min # Cap at 80% until completion
    when :completed
      100
    when :failed
      0
    else
      0
    end
  end

  # Broadcast methods for Turbo Streams
  def broadcast_search_update(search)
    Turbo::StreamsChannel.broadcast_replace_to(
      "search_#{search.id}",
      target: "search_status",
      partial: "searches/status",
      locals: { search: search }
    )
  end

  def broadcast_search_results(search)
    Turbo::StreamsChannel.broadcast_replace_to(
      "search_#{search.id}",
      target: "search_results",
      partial: "searches/results",
      locals: { search_results: search.search_results.includes(:document).ordered_by_relevance }
    )
  end

  def broadcast_ai_response(search)
    # Prepare the same data structure as in the show action
    search_results = search.search_results.includes(:document).ordered_by_relevance

    ai_response_data = {
      search_results: search_results,
      total_sources: search_results.count,
      top_sources: search_results.limit(5),
      response: search.ai_response,
      follow_up_questions: search.follow_up_questions
    }

    Turbo::StreamsChannel.broadcast_replace_to(
      "search_#{search.id}",
      target: "ai_response",
      partial: "searches/ai_response",
      locals: {
        search: search,
        ai_response_data: ai_response_data
      }
    )
  end

  # Class methods for broadcasting from jobs
  def self.broadcast_status_update(search_id)
    search = Search.find(search_id)
    new.broadcast_search_update(search)
  end

  def self.broadcast_results_update(search_id)
    search = Search.find(search_id)
    new.broadcast_search_results(search)
  end

  def self.broadcast_ai_response_ready(search_id)
    search = Search.find(search_id)
    new.broadcast_ai_response(search)
  end
end
