class CreateSearchResults < ActiveRecord::Migration[8.0]
  def change
    create_table :search_results do |t|
      t.references :search, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true
      t.float :relevance_score

      t.timestamps
    end
  end
end
