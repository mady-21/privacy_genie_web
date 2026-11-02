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

ActiveRecord::Schema[8.1].define(version: 2026_11_02_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "document_chunks", force: :cascade do |t|
    t.date "article_effective_date"
    t.string "article_number", null: false
    t.string "article_title"
    t.string "chapter"
    t.string "chunk_id", null: false
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.vector "embedding", limit: 1024, null: false
    t.boolean "is_effective", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "part_count", null: false
    t.integer "part_index", null: false
    t.integer "position", null: false
    t.string "section"
    t.text "text", null: false
    t.datetime "updated_at", null: false
    t.index ["chunk_id"], name: "index_document_chunks_on_chunk_id", unique: true
    t.index ["document_id"], name: "index_document_chunks_on_document_id"
    t.check_constraint "\"position\" > 0", name: "document_chunks_position_check"
    t.check_constraint "is_effective OR article_effective_date IS NOT NULL", name: "document_chunks_pending_date_check"
    t.check_constraint "length(btrim(text)) > 0", name: "document_chunks_text_check"
    t.check_constraint "part_index >= 1 AND part_index <= part_count", name: "document_chunks_part_check"
    t.unique_constraint ["document_id", "position"], deferrable: :immediate, name: "document_chunks_position_unique"
  end

  create_table "documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "document_type", null: false
    t.string "embedding_model"
    t.date "law_effective_date"
    t.string "law_number"
    t.string "name", null: false
    t.string "source_key", null: false
    t.datetime "updated_at", null: false
    t.index ["source_key"], name: "index_documents_on_source_key", unique: true
    t.check_constraint "document_type::text = ANY (ARRAY['act'::character varying, 'decree'::character varying, 'guide'::character varying]::text[])", name: "documents_type_check"
  end

  add_foreign_key "document_chunks", "documents"
end
