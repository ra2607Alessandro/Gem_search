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

ActiveRecord::Schema[8.0].define(version: 2025_09_03_171333) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "citations", force: :cascade do |t|
    t.bigint "search_result_id", null: false
    t.text "source_url"
    t.text "snippet"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["search_result_id"], name: "index_citations_on_search_result_id"
  end

  create_table "documents", force: :cascade do |t|
    t.text "url"
    t.text "title"
    t.text "content"
    t.datetime "scraped_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "search_results", force: :cascade do |t|
    t.bigint "search_id", null: false
    t.bigint "document_id", null: false
    t.float "relevance_score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id"], name: "index_search_results_on_document_id"
    t.index ["search_id"], name: "index_search_results_on_search_id"
  end

  create_table "searches", force: :cascade do |t|
    t.text "query"
    t.text "goal"
    t.text "rules"
    t.string "user_ip"
    t.integer "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "ai_response"
    t.jsonb "follow_up_questions"
  end

  add_foreign_key "citations", "search_results"
  add_foreign_key "search_results", "documents"
  add_foreign_key "search_results", "searches"
end
