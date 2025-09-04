class AddEmbeddingToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :embedding, :vector
  end
end
