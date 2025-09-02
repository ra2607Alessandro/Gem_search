class Search::WebSearchService
  def initialize(query, options = {})
    @query = query
    @options = options
  end

  def call
    # TODO: Implement web search using Google Custom Search API
    # This will be built by Cursor
    []
  end

  private

  attr_reader :query, :options
end