class AddUserToSearches < ActiveRecord::Migration[8.0]
  def change
    add_reference :searches, :user, foreign_key: true, index: true, null: true
  end
end
