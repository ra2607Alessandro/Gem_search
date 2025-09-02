class CreateDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :documents do |t|
      t.text :url, null: false
      t.text :title, null: false
      t.text :content, null: false
      t.vector :embedding, limit: 1536  # OpenAI ada-002 embedding size
      t.datetime :scraped_at
      t.timestamps
    end
    
    add_index :documents, :url, unique: true
    add_index :documents, :embedding, using: :ivfflat, opclass: :vector_cosine_ops
  end
end
