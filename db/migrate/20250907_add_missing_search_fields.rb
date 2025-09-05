class AddMissingSearchFields < ActiveRecord::Migration[8.0]
  def change
    # Add missing fields if they don't exist
    unless column_exists?(:searches, :expected_documents_count)
      add_column :searches, :expected_documents_count, :integer
    end

    # Add index for status queries
    add_index :searches, :status unless index_exists?(:searches, :status)
    add_index :searches, [:status, :updated_at] unless index_exists?(:searches, [:status, :updated_at])
  end
end
