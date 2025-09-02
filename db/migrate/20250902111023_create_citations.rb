class CreateCitations < ActiveRecord::Migration[8.0]
  def change
    create_table :citations do |t|
      t.references :search_result, null: false, foreign_key: true
      t.text :source_url
      t.text :snippet

      t.timestamps
    end
  end
end
