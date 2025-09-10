require 'rails_helper'

RSpec.describe "Searches", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/searches/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /create" do
    it "returns http success" do
      get "/searches/create"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/searches/show"
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /searches when rate limit exceeded" do
    it "renders limit reached page" do
      user = double("User", remaining_searches: 0)
      allow_any_instance_of(SearchesController).to receive(:current_user).and_return(user)

      post "/searches", params: { search: { query: "test" } }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include("Search limit reached")
      expect(response.body).to include("Upgrade")
    end
  end

  describe "Complete search flow with AI response" do
    let(:search_params) do
      {
        search: {
          query: "What is Ruby on Rails?",
          goal: "Learn about the framework",
          rules: "Be concise and accurate"
        }
      }
    end

    before do
      # Stub external services to avoid real API calls during testing
      allow_any_instance_of(Search::WebSearchService).to receive(:search).and_return([
        { title: "Ruby on Rails - Wikipedia", url: "https://en.wikipedia.org/wiki/Ruby_on_Rails", snippet: "Ruby on Rails is a web framework" },
        { title: "Rails Guides", url: "https://guides.rubyonrails.org/", snippet: "Official Rails documentation" }
      ])

      allow_any_instance_of(Scraping::ContentScraperService).to receive(:call).and_return({
        success: true,
        title: "Ruby on Rails - Wikipedia",
        content: "Ruby on Rails is a web application framework written in Ruby",
        cleaned_content: "Ruby on Rails is a web application framework written in Ruby",
        content_chunks: ["Ruby on Rails is a web application framework written in Ruby"],
        error: nil
      })

      allow_any_instance_of(Ai::EmbeddingService).to receive(:call).and_return([0.1] * 1536)
      allow_any_instance_of(Ai::ResponseGenerationService).to receive(:generate_response).and_return({
        answer: "Ruby on Rails is a web application framework written in Ruby that follows the MVC pattern.",
        follow_ups: ["What are the main features of Rails?", "How do I install Rails?"]
      })
    end

    it "creates a search, processes it, and generates AI response" do
      # Create search
      post "/searches", params: search_params
      expect(response).to have_http_status(:redirect)

      search = Search.last
      expect(search).to be_present
      expect(search.query).to eq("What is Ruby on Rails?")
      expect(search.status).to eq("pending")

      # Process the search (simulate background job)
      SearchProcessingJob.perform_now(search.id)
      search.reload

      # Should have moved to scraping status and created search results
      expect(search.status).to eq("scraping")
      expect(search.search_results.count).to eq(2)

      # Simulate scraping completion for all documents
      search.search_results.each do |result|
        WebScrapingJob.perform_now(
          result.document.id,
          search.id,
          search.search_results.index(result),
          { title: result.document.title, url: result.document.url }
        )
      end

      # AI response should now be generated
      search.reload
      expect(search.status).to eq("completed")
      expect(search.ai_response).to be_present
      expect(search.ai_response).to include("Ruby on Rails")
      expect(search.follow_up_questions).to be_an(Array)
      expect(search.follow_up_questions.count).to eq(2)

      # Test the show page displays AI response
      get "/searches/#{search.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("AI Response")
      expect(response.body).to include("Ruby on Rails")
    end

    it "handles scraping failures gracefully" do
      # Create search
      post "/searches", params: search_params
      expect(response).to have_http_status(:redirect)

      search = Search.last

      # Process search but fail scraping
      allow_any_instance_of(Scraping::ContentScraperService).to receive(:call).and_return({
        success: false,
        title: "",
        content: "",
        cleaned_content: "",
        content_chunks: [],
        error: "Scraping failed"
      })

      SearchProcessingJob.perform_now(search.id)
      search.reload

      # Should still be in scraping status
      expect(search.status).to eq("scraping")

      # Simulate failed scraping jobs
      search.search_results.each do |result|
        WebScrapingJob.perform_now(
          result.document.id,
          search.id,
          search.search_results.index(result),
          { title: result.document.title, url: result.document.url }
        )
      end

      # AI response should not be generated due to no content
      search.reload
      expect(search.status).to eq("scraping") # Still waiting for content
      expect(search.ai_response).to be_nil
    end

    it "handles AI response generation failure" do
      # Create search
      post "/searches", params: search_params
      expect(response).to have_http_status(:redirect)

      search = Search.last

      # Process search successfully
      SearchProcessingJob.perform_now(search.id)
      search.reload

      # Simulate successful scraping
      search.search_results.each do |result|
        WebScrapingJob.perform_now(
          result.document.id,
          search.id,
          search.search_results.index(result),
          { title: result.document.title, url: result.document.url }
        )
      end

      # Now simulate AI generation failure
      allow_any_instance_of(Ai::ResponseGenerationService).to receive(:generate_response).and_return(nil)

      # Manually trigger AI generation (normally done by ScrapingCompletionService)
      AiResponseGenerationJob.perform_now(search.id)

      search.reload
      expect(search.status).to eq("retryable")
      expect(search.ai_response).to be_nil
    end
  end
end
