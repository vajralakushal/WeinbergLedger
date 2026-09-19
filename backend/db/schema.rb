# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_19_190917) do
  create_table "AUDIT_LOG", primary_key: "ID", force: :cascade do |t|
    t.integer "BOOK_ID", null: false
    t.text "EDITOR", null: false
    t.text "FIELD", null: false
    t.text "IP"
    t.text "NEW_VALUE"
    t.text "OLD_VALUE"
    t.text "TIMESTAMP", null: false
  end

  create_table "LIBRARY", primary_key: "ID", id: :integer, default: nil, force: :cascade do |t|
    t.text "BORROWER"
    t.text "CREATION_DATE"
    t.text "CREATOR"
    t.text "IDENTIFIER"
    t.text "LOCATION"
    t.integer "OWNER", null: false
    t.text "PUBLISHER"
    t.text "SERIES"
    t.text "SUBJECT"
    t.text "TITLE", null: false
  end

  create_table "SESSIONS", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["token_digest"], name: "index_SESSIONS_on_token_digest", unique: true
    t.index ["user_id"], name: "index_SESSIONS_on_user_id"
  end

  create_table "USERS", primary_key: "user_id", force: :cascade do |t|
    t.boolean "admin_status", default: false, null: false
    t.string "approval_status", default: "PENDING", null: false
    t.datetime "created_at", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.boolean "must_change_password", default: false, null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["username"], name: "index_USERS_on_username", unique: true
  end

  add_foreign_key "SESSIONS", "USERS", column: "user_id", primary_key: "user_id"
end
