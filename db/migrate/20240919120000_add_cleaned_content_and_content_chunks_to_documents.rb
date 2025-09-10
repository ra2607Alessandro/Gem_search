class AddCleanedContentAndContentChunksToDocuments < ActiveRecord::Migration[7.1]
  def change
    add_column :documents, :cleaned_content, :text
    add_column :documents, :content_chunks, :text, array: true, default: []
  end
end
