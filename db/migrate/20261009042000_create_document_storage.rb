class CreateDocumentStorage < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.string :source_key, null: false
      t.string :name, null: false
      t.string :document_type, null: false
      t.string :law_number
      t.string :law_effective_date
      t.timestamps
    end
    add_index :documents, :source_key, unique: true
    add_check_constraint :documents, "document_type IN ('act', 'decree', 'guide')", name: "documents_type_check"

    create_table :document_supplements do |t|
      t.references :document, null: false, foreign_key: true
      t.string :source_key, null: false
      t.text :heading, null: false
      t.string :law_number
      t.date :promulgation_date
      t.jsonb :preamble, null: false, default: []
      t.timestamps
    end
    add_index :document_supplements, [ :document_id, :source_key ], unique: true

    create_table :document_chunks do |t|
      t.references :document, null: false, foreign_key: true
      t.references :document_supplement, foreign_key: true
      t.integer :position, null: false
      t.string :article_number, null: false
      t.string :article_title
      t.string :chapter
      t.string :section
      t.text :text, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :document_chunks, [ :document_id, :position ], unique: true
    add_check_constraint :document_chunks, "position > 0", name: "document_chunks_position_check"
    add_check_constraint :document_chunks, "length(btrim(text)) > 0", name: "document_chunks_text_check"
  end
end
