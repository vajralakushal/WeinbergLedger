class CreateUsersAndSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :USERS, primary_key: :user_id do |t|
      t.boolean  :admin_status,         null: false, default: false
      t.string   :first_name,           null: false
      t.string   :last_name,            null: false
      t.string   :username,             null: false
      t.string   :password_digest,      null: false
      t.string   :approval_status,      null: false, default: "PENDING"
      t.boolean  :must_change_password, null: false, default: false
      t.timestamps
    end
    add_index :USERS, :username, unique: true

    create_table :SESSIONS do |t|
      t.integer  :user_id,      null: false
      t.string   :token_digest, null: false
      t.datetime :expires_at,   null: false
      t.timestamps
    end
    add_index :SESSIONS, :token_digest, unique: true
    add_index :SESSIONS, :user_id
    add_foreign_key :SESSIONS, :USERS, column: :user_id, primary_key: :user_id
  end
end
