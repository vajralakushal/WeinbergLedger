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

ActiveRecord::Schema[8.1].define(version: 2026_09_19_185105) do
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
end
