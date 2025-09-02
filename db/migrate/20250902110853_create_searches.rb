class CreateSearches < ActiveRecord::Migration[8.0]
  def change
    create_table :searches do |t|
      t.text :query
      t.text :goal
      t.text :rules
      t.string :user_ip
      t.integer :status

      t.timestamps
    end
  end
end
