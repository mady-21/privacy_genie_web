require "test_helper"

class Documents::SyncTest < ActiveSupport::TestCase
  setup do
    @client = FakeDocClient.new
    @sync = Documents::Sync.new(client: @client)
  end

  test "first sync creates the document and its chunks" do
    @client.documents["act"] = document_payload([
      chunk_payload("act:제1조:1", 1, article_title: "목적", chapter: "제1장 총칙", metadata: { "created" => "본조신설" }),
      chunk_payload("act:제75조:2:part1", 2, article_number: "제75조", part_index: 1, part_count: 2,
        is_effective: false, article_effective_date: "2027-07-01")
    ])

    result = @sync.call("act")

    assert_equal Documents::Sync::Result.new(source_key: "privacy", inserted: 2, deleted: 0, kept: 0, reloaded: false), result
    document = Document.find_by!(source_key: "privacy")
    assert_equal [ "act", "개인정보 보호법", "법률 제21445호", Date.new(2026, 9, 11), FakeDocClient::MODEL ],
      [ document.document_type, document.name, document.law_number, document.law_effective_date, document.embedding_model ]

    first, pending = document.document_chunks.ordered.to_a
    assert_equal [ "act:제1조:1", 1, "목적", "제1장 총칙", true, nil, { "created" => "본조신설" } ],
      [ first.chunk_id, first.position, first.article_title, first.chapter, first.is_effective, first.article_effective_date, first.metadata ]
    assert_in_delta 1.0, first.embedding[1], 1e-6
    assert_equal [ "제75조", 1, 2, false, Date.new(2027, 7, 1) ],
      [ pending.article_number, pending.part_index, pending.part_count, pending.is_effective, pending.article_effective_date ]
  end

  test "syncing the same response again changes nothing" do
    @client.documents["act"] = document_payload([ chunk_payload("act:제1조:1", 1), chunk_payload("act:제2조:1", 2) ])
    @sync.call("act")
    before = DocumentChunk.order(:id).pluck(:id, :created_at, :updated_at)
    document_updated_at = Document.sole.updated_at

    travel 1.minute do
      result = @sync.call("act")
      assert_equal [ 0, 0, 2, false ], [ result.inserted, result.deleted, result.kept, result.reloaded ]
    end

    assert_equal before, DocumentChunk.order(:id).pluck(:id, :created_at, :updated_at)
    assert_equal document_updated_at, Document.sole.updated_at
  end

  test "upserts by chunk id, deletes missing chunks and reorders positions" do
    @client.documents["act"] = document_payload([
      chunk_payload("act:제1조:1", 1), chunk_payload("act:제2조:1", 2), chunk_payload("act:제3조:1", 3)
    ])
    @sync.call("act")
    ids = DocumentChunk.pluck(:chunk_id, :id).to_h

    # 제3조와 제1조의 position을 맞바꾸고, 제2조를 지우고, 제4조를 더한다.
    @client.documents["act"] = document_payload([
      chunk_payload("act:제3조:1", 1),
      chunk_payload("act:제1조:1", 2, text: "바뀐 본문"),
      chunk_payload("act:제4조:1", 3)
    ])
    result = @sync.call("act")

    assert_equal [ 1, 1, 2 ], [ result.inserted, result.deleted, result.kept ]
    chunks = DocumentChunk.ordered.to_a
    assert_equal %w[act:제3조:1 act:제1조:1 act:제4조:1], chunks.map(&:chunk_id)
    assert_equal ids["act:제3조:1"], chunks[0].id
    assert_equal ids["act:제1조:1"], chunks[1].id
    assert_equal "바뀐 본문", chunks[1].text
    assert_not DocumentChunk.exists?(chunk_id: "act:제2조:1")
  end

  test "a new embedding model reloads every chunk instead of mixing vectors" do
    @client.documents["act"] = document_payload([ chunk_payload("act:제1조:1", 1), chunk_payload("act:제2조:1", 2) ])
    @sync.call("act")
    old_ids = DocumentChunk.pluck(:id)

    @client.documents["act"] = document_payload([ chunk_payload("act:제1조:1", 1), chunk_payload("act:제2조:1", 2) ],
      embedding_model: "other/model")
    result = @sync.call("act")

    assert_equal [ 2, 2, 0, true ], [ result.inserted, result.deleted, result.kept, result.reloaded ]
    assert_equal "other/model", Document.sole.embedding_model
    assert_empty DocumentChunk.where(id: old_ids)
    assert_equal 2, DocumentChunk.count
  end

  test "invalid responses raise before touching the database" do
    valid_chunks = [ chunk_payload("act:제1조:1", 1), chunk_payload("act:제2조:1", 2) ]
    invalid_payloads = {
      "document type" => document_payload(valid_chunks, document_type: "decree"),
      "dimension" => document_payload(valid_chunks, embedding_dimension: 768),
      "vector length" => document_payload([ chunk_payload("act:제1조:1", 1, embedding: [ 1.0, 0.0 ]) ]),
      "vector values" => document_payload([ chunk_payload("act:제1조:1", 1, embedding: Array.new(1024, "x")) ]),
      "empty chunks" => document_payload([]),
      "duplicate chunk ids" => document_payload([ chunk_payload("act:제1조:1", 1), chunk_payload("act:제1조:1", 2) ]),
      "positions" => document_payload([ chunk_payload("act:제1조:1", 1), chunk_payload("act:제2조:1", 3) ]),
      "date" => document_payload(valid_chunks, law_effective_date: "2026. 9. 11.")
    }

    invalid_payloads.each do |name, payload|
      @client.documents["act"] = payload
      assert_raises(Documents::Sync::InvalidPayload, name) { @sync.call("act") }
      assert_equal 0, Document.count, name
      assert_equal 0, DocumentChunk.count, name
    end
  end

  test "rejects a source key already stored as another document type" do
    Document.create!(source_key: "privacy", name: "개인정보 보호법", document_type: "decree")
    @client.documents["act"] = document_payload([ chunk_payload("act:제1조:1", 1) ])

    assert_raises(Documents::Sync::InvalidPayload) { @sync.call("act") }
    assert_equal 0, DocumentChunk.count
  end

  test "rejects chunk ids that belong to another document" do
    @client.documents["act"] = document_payload([ chunk_payload("shared:제1조:1", 1) ])
    @sync.call("act")
    @client.documents["decree"] = document_payload([ chunk_payload("shared:제1조:1", 1) ],
      document_type: "decree", source_key: "privacy_decree")

    assert_raises(Documents::Sync::InvalidPayload) { @sync.call("decree") }
    assert_equal [ "privacy" ], Document.pluck(:source_key)
  end

  test "a database error rolls back the whole document" do
    @client.documents["act"] = document_payload([ chunk_payload("act:제1조:1", 1) ])
    @sync.call("act")

    # 미시행인데 시행일이 없는 청크는 DB 체크 제약에 걸린다.
    @client.documents["act"] = document_payload([ chunk_payload("act:제2조:1", 1, is_effective: false) ],
      law_number: "법률 제99999호")
    assert_raises(ActiveRecord::StatementInvalid) { @sync.call("act") }

    assert_equal "법률 제21445호", Document.sole.law_number
    assert_equal [ "act:제1조:1" ], DocumentChunk.pluck(:chunk_id)
  end

  test "each document commits on its own" do
    @client.documents["act"] = document_payload([ chunk_payload("act:제1조:1", 1) ])
    @client.documents["decree"] = PrivacyGenieDoc::Client::ServiceUnavailable.new("rebuild를 다시 하세요")

    @sync.call("act")
    error = assert_raises(PrivacyGenieDoc::Client::ServiceUnavailable) { @sync.call("decree") }

    assert_includes error.message, "rebuild"
    assert_equal [ "privacy" ], Document.pluck(:source_key)
    assert_equal 1, DocumentChunk.count
  end

  private

  def document_payload(chunks, **overrides)
    {
      "source_key" => "privacy",
      "document_type" => "act",
      "name" => "개인정보 보호법",
      "law_number" => "법률 제21445호",
      "law_effective_date" => "2026-09-11",
      "embedding_model" => FakeDocClient::MODEL,
      "embedding_dimension" => DocumentChunk::EMBEDDING_DIMENSION,
      "chunks" => chunks
    }.merge(overrides.stringify_keys)
  end

  def chunk_payload(chunk_id, position, **overrides)
    {
      "chunk_id" => chunk_id,
      "position" => position,
      "article_number" => chunk_id.split(":").second,
      "article_title" => nil,
      "chapter" => nil,
      "section" => nil,
      "text" => "#{chunk_id} 본문",
      "part_index" => 1,
      "part_count" => 1,
      "is_effective" => true,
      "article_effective_date" => nil,
      "metadata" => {},
      "embedding" => embedding(position => 1)
    }.merge(overrides.stringify_keys)
  end
end
