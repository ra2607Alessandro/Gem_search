class AddQueryEmbeddingToSearches < ActiveRecord::Migration[7.1]
  def change
    add_column :searches, :query_embedding, :vector, limit: 1536
  end
end
