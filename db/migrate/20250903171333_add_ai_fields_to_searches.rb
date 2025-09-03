class AddAiFieldsToSearches < ActiveRecord::Migration[8.0]
  def change
    add_column :searches, :ai_response, :text
    add_column :searches, :follow_up_questions, :jsonb
  end
end
