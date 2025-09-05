class AddExpectedDocumentsCountToSearches < ActiveRecord::Migration[8.0]
  def change
    add_column :searches, :expected_documents_count, :integer
  end
end
