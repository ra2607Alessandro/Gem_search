require 'rails_helper'

RSpec.describe AiResponseGenerationJob, type: :job do
  include ActiveJob::TestHelper

  let(:search) { create(:search, status: :scraping) }

  before do
    allow(Ai::ResponseGenerationService).to receive(:new).and_return(service)
  end

  context 'when generation succeeds' do
    let(:service) { instance_double(Ai::ResponseGenerationService, generate_response: {response: 'Hello', follow_up_questions: []}) }

    it 'completes the search and queues embeddings' do
      doc = create(:document, content: 'abcde', search_results: [build(:search_result, search: search)])
      expect_any_instance_of(Document).to receive(:generate_embedding!).at_least(:once)
      perform_enqueued_jobs { described_class.perform_now(search.id) }
      search.reload
      expect(search).to be_completed
      expect(search.ai_response).to eq('Hello')
    end
  end

  context 'when generation returns error' do
    let(:service) { instance_double(Ai::ResponseGenerationService, generate_response: {error: 'failure'}) }

    it 'marks search as retryable with error message' do
      described_class.perform_now(search.id)
      search.reload
      expect(search).to be_retryable
      expect(search.error_message).to eq('failure')
    end
  end

  context 'when insufficient sources' do
    let(:service) do
      instance_double(Ai::ResponseGenerationService).tap do |s|
        allow(s).to receive(:generate_response).and_raise(Ai::ResponseGenerationService::InsufficientSourcesError, 'too few')
      end
    end

    it 'marks search as failed with message' do
      described_class.perform_now(search.id)
      search.reload
      expect(search).to be_failed
      expect(search.error_message).to eq('too few')
    end
  end
end
