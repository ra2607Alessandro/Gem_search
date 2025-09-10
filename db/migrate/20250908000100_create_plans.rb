class CreatePlans < ActiveRecord::Migration[8.0]
  def change
    create_table :plans do |t|
      t.string :name
      t.integer :price_cents, default: 0
      t.string :interval

      t.timestamps
    end
  end
end
