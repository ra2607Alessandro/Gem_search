class FixDocumentConstraints < ActiveRecord::Migration[8.0]
  def change
    # Remove NOT NULL constraint from content column
    change_column_null :documents, :content, true

    # Add index for scraped_at to optimize queries
    add_index :documents, :scraped_at unless index_exists?(:documents, :scraped_at)

    # Add a partial index for documents with embeddings
    add_index :documents, [:id, :scraped_at], where: "embedding IS NOT NULL", name: 'index_documents_with_embeddings'
  end
end
