class AddErrorMessageToSearches < ActiveRecord::Migration[8.0]
  def change
    add_column :searches, :error_message, :text
  end
end
