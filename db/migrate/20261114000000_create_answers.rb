# 사용자 질문과 LLM 답변. 질문은 Answers::Masking을 거친 것만 저장하고, 보관 기간이 지나면 본문을 지운다(purged_at).
# 근거 조문은 청크 FK 대신 텍스트 스냅샷으로 남긴다. documents:sync가 청크를 지우거나 다시 넣기 때문이다.
class CreateAnswers < ActiveRecord::Migration[8.1]
  def change
    create_table :answers do |t|
      # 답변 URL에 쓰는 추측 불가 토큰. 순번 id를 쓰면 남의 질문을 열어 볼 수 있다.
      t.string :token, null: false
      t.text :question
      t.string :masked_kinds, array: true, null: false, default: []
      t.string :status, null: false, default: "pending"
      t.string :outcome
      t.text :body
      t.integer :dropped_citation_numbers, array: true, null: false, default: []
      t.string :error_kind
      t.text :error_message
      t.string :provider
      t.string :model
      t.string :stop_reason
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :latency_ms
      t.datetime :completed_at
      t.datetime :purged_at
      t.timestamps

      t.index :token, unique: true
      t.index :created_at
      t.check_constraint "status IN ('pending', 'searching', 'generating', 'completed', 'failed')", name: "answers_status_check"
      t.check_constraint "outcome IS NULL OR outcome IN ('answered', 'no_basis', 'truncated', 'refused')", name: "answers_outcome_check"
      t.check_constraint "error_kind IS NULL OR error_kind IN ('temporary', 'unavailable')", name: "answers_error_kind_check"
      t.check_constraint "question IS NOT NULL OR purged_at IS NOT NULL", name: "answers_question_check"
    end

    create_table :answer_citations do |t|
      t.references :answer, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :number, null: false
      t.boolean :cited, null: false, default: false
      t.string :document_type, null: false
      t.string :document_name, null: false
      t.string :article_number, null: false
      t.string :article_title
      t.string :chapter
      t.integer :part_index, null: false
      t.integer :part_count, null: false
      t.text :text, null: false
      t.string :status, null: false
      t.date :effective_date
      t.date :pending_amendment_date
      t.float :similarity, null: false
      t.timestamps

      t.index [ :answer_id, :number ], unique: true
      t.check_constraint "number > 0", name: "answer_citations_number_check"
      t.check_constraint "status IN ('effective', 'pending')", name: "answer_citations_status_check"
    end
  end
end
