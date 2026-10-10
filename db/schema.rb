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

ActiveRecord::Schema[8.1].define(version: 2026_10_09_042000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "document_chunks", force: :cascade do |t|
    t.string "article_number", null: false
    t.string "article_title"
    t.string "chapter"
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.bigint "document_supplement_id"
    t.jsonb "metadata", default: {}, null: false
    t.integer "position", null: false
    t.string "section"
    t.text "text", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id", "position"], name: "index_document_chunks_on_document_id_and_position", unique: true
    t.index ["document_id"], name: "index_document_chunks_on_document_id"
    t.index ["document_supplement_id"], name: "index_document_chunks_on_document_supplement_id"
    t.check_constraint "\"position\" > 0", name: "document_chunks_position_check"
    t.check_constraint "length(btrim(text)) > 0", name: "document_chunks_text_check"
  end

  create_table "document_supplements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.text "heading", null: false
    t.string "law_number"
    t.jsonb "preamble", default: [], null: false
    t.date "promulgation_date"
    t.string "source_key", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id", "source_key"], name: "index_document_supplements_on_document_id_and_source_key", unique: true
    t.index ["document_id"], name: "index_document_supplements_on_document_id"
  end

  create_table "documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "document_type", null: false
    t.string "law_effective_date"
    t.string "law_number"
    t.string "name", null: false
    t.string "source_key", null: false
    t.datetime "updated_at", null: false
    t.index ["source_key"], name: "index_documents_on_source_key", unique: true
    t.check_constraint "document_type::text = ANY (ARRAY['act'::character varying, 'decree'::character varying, 'guide'::character varying]::text[])", name: "documents_type_check"
  end

  add_foreign_key "document_chunks", "document_supplements"
  add_foreign_key "document_chunks", "documents"
  add_foreign_key "document_supplements", "documents"
end
