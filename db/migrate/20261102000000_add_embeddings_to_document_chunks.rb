class AddEmbeddingsToDocumentChunks < ActiveRecord::Migration[8.1]
  def up
    enable_extension "vector"

    # chunk_id·벡터가 없는 기존 청크는 남길 수 없다. doc API에서 다시 동기화하면 그대로 복원된다.
    execute "DELETE FROM document_chunks"

    # doc이 부칙을 더 이상 내주지 않으므로 부칙 테이블과 연결 컬럼을 없앤다.
    remove_reference :document_chunks, :document_supplement, foreign_key: true, index: true
    drop_table :document_supplements

    add_column :documents, :embedding_model, :string
    change_column :documents, :law_effective_date, :date, using: "law_effective_date::date"

    add_column :document_chunks, :chunk_id, :string, null: false
    add_column :document_chunks, :part_index, :integer, null: false
    add_column :document_chunks, :part_count, :integer, null: false
    add_column :document_chunks, :is_effective, :boolean, null: false, default: true
    add_column :document_chunks, :article_effective_date, :date
    add_column :document_chunks, :embedding, :vector, limit: 1024, null: false
    add_index :document_chunks, :chunk_id, unique: true
    add_check_constraint :document_chunks, "part_index BETWEEN 1 AND part_count", name: "document_chunks_part_check"
    add_check_constraint :document_chunks, "is_effective OR article_effective_date IS NOT NULL",
      name: "document_chunks_pending_date_check"

    # 유니크 인덱스는 행마다 검사해서, 동기화 upsert로 position이 밀리면 문장 도중에 잠깐 겹친 행 때문에 실패한다.
    # DEFERRABLE 제약은 문장이 끝난 뒤에 검사하므로 한 문장 안의 이동은 통과한다.
    remove_index :document_chunks, [ :document_id, :position ]
    add_unique_constraint :document_chunks, [ :document_id, :position ],
      deferrable: :immediate, name: "document_chunks_position_unique"
  end

  def down
    execute "DELETE FROM document_chunks"

    remove_unique_constraint :document_chunks, name: "document_chunks_position_unique"
    add_index :document_chunks, [ :document_id, :position ], unique: true

    remove_check_constraint :document_chunks, name: "document_chunks_pending_date_check"
    remove_check_constraint :document_chunks, name: "document_chunks_part_check"
    remove_index :document_chunks, :chunk_id
    remove_column :document_chunks, :embedding
    remove_column :document_chunks, :article_effective_date
    remove_column :document_chunks, :is_effective
    remove_column :document_chunks, :part_count
    remove_column :document_chunks, :part_index
    remove_column :document_chunks, :chunk_id

    change_column :documents, :law_effective_date, :string, using: "law_effective_date::text"
    remove_column :documents, :embedding_model

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
    add_reference :document_chunks, :document_supplement, foreign_key: true

    disable_extension "vector"
  end
end
