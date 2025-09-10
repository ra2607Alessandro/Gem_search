class CreatePlans < ActiveRecord::Migration[7.1]
  def change
    create_table :plans do |t|
      t.string :name
      t.integer :daily_search_limit, null: false, default: 100

      t.timestamps
    end
  end
end
