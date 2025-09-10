class CreateSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: true
      t.string :status
      t.string :billing_id
      t.datetime :current_period_end

      t.timestamps
    end
  end
end
