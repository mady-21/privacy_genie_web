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

ActiveRecord::Schema[8.1].define(version: 2026_11_14_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "answer_citations", force: :cascade do |t|
    t.bigint "answer_id", null: false
    t.string "article_number", null: false
    t.string "article_title"
    t.string "chapter"
    t.boolean "cited", default: false, null: false
    t.datetime "created_at", null: false
    t.string "document_name", null: false
    t.string "document_type", null: false
    t.date "effective_date"
    t.integer "number", null: false
    t.integer "part_count", null: false
    t.integer "part_index", null: false
    t.date "pending_amendment_date"
    t.float "similarity", null: false
    t.string "status", null: false
    t.text "text", null: false
    t.datetime "updated_at", null: false
    t.index ["answer_id", "number"], name: "index_answer_citations_on_answer_id_and_number", unique: true
    t.check_constraint "number > 0", name: "answer_citations_number_check"
    t.check_constraint "status::text = ANY (ARRAY['effective'::character varying, 'pending'::character varying]::text[])", name: "answer_citations_status_check"
  end

  create_table "answers", force: :cascade do |t|
    t.text "body"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "dropped_citation_numbers", default: [], null: false, array: true
    t.string "error_kind"
    t.text "error_message"
    t.integer "input_tokens"
    t.integer "latency_ms"
    t.string "masked_kinds", default: [], null: false, array: true
    t.string "model"
    t.string "outcome"
    t.integer "output_tokens"
    t.string "provider"
    t.datetime "purged_at"
    t.text "question"
    t.string "status", default: "pending", null: false
    t.string "stop_reason"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_answers_on_created_at"
    t.index ["token"], name: "index_answers_on_token", unique: true
    t.check_constraint "error_kind IS NULL OR (error_kind::text = ANY (ARRAY['temporary'::character varying, 'unavailable'::character varying]::text[]))", name: "answers_error_kind_check"
    t.check_constraint "outcome IS NULL OR (outcome::text = ANY (ARRAY['answered'::character varying, 'no_basis'::character varying, 'truncated'::character varying, 'refused'::character varying]::text[]))", name: "answers_outcome_check"
    t.check_constraint "question IS NOT NULL OR purged_at IS NOT NULL", name: "answers_question_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'searching'::character varying, 'generating'::character varying, 'completed'::character varying, 'failed'::character varying]::text[])", name: "answers_status_check"
  end

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

  add_foreign_key "answer_citations", "answers", on_delete: :cascade
  add_foreign_key "document_chunks", "documents"
end
