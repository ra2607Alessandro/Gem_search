class AddEmbeddingToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :embedding, :vector, limit: 1536
    add_index :documents, :embedding, using: :ivfflat, opclass: :vector_cosine_ops
    
    # Also add the missing constraint on URL
    change_column_null :documents, :url, false
    change_column_null :documents, :title, false
    change_column_null :documents, :content, false
    
    # Add unique index on URL if not exists
    add_index :documents, :url, unique: true unless index_exists?(:documents, :url)
  end
end