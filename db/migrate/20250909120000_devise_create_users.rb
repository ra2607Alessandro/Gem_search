# frozen_string_literal: true

class DeviseCreateUsers < ActiveRecord::Migration[8.0]
  def change
    # Bring existing users table in line with Devise expectations
    change_column_default :users, :email, ""
    change_column_null :users, :email, false, ""

    # Devise fields
    add_column :users, :encrypted_password, :string, null: false, default: ""
    add_column :users, :reset_password_token, :string
    add_column :users, :reset_password_sent_at, :datetime
    add_column :users, :remember_created_at, :datetime

    # Indexes
    add_index :users, :email,                unique: true
    add_index :users, :reset_password_token, unique: true
    # add_index :users, :confirmation_token,   unique: true
    # add_index :users, :unlock_token,         unique: true
  end
end

