require 'rails_helper'

RSpec.describe Ai::ResponseGenerationService, type: :service do
  let(:search) { create(:search, status: :scraping) }

  before do
    Rails.application.config.x.openai_client = openai_client
  end

  describe '#generate_response' do
    context 'when OpenAI returns empty content' do
      let(:openai_client) do
        instance_double(OpenAI::Client, chat: {'choices' => [{'message' => {'content' => ''}}]})
      end

      before do
        create(:document, content: 'abcde', search_results: [build(:search_result, search: search)])
      end

      it 'returns an empty response error' do
        result = described_class.new(search).generate_response
        expect(result).to eq(error: 'Empty response from OpenAI')
      end
    end

    context 'when OpenAI times out' do
      let(:openai_client) do
        instance_double(OpenAI::Client)
      end

      before do
        allow(openai_client).to receive(:chat).and_raise(Timeout::Error)
        create(:document, content: 'abcde', search_results: [build(:search_result, search: search)])
      end

      it 'retries and returns timeout error' do
        service = described_class.new(search)
        expect(openai_client).to receive(:chat).exactly(3).times
        result = service.generate_response
        expect(result).to eq(error: 'OpenAI response timed out after 60s')
      end
    end

    context 'when OpenAI client is missing' do
      let(:openai_client) { nil }

      it 'returns configuration error' do
        result = described_class.new(search).generate_response
        expect(result).to eq(error: 'OpenAI client not configured')
      end
    end

    context 'with insufficient sources' do
      let(:openai_client) { instance_double(OpenAI::Client) }

      it 'raises InsufficientSourcesError' do
        expect {
          described_class.new(search).generate_response
        }.to raise_error(Ai::ResponseGenerationService::InsufficientSourcesError)
      end
    end
  end
end
