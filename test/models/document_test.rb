require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  setup do
    @document = Document.create!(source_key: "test_privacy_act", name: "개인정보 보호법", document_type: "act")
  end

  test "requires source key and name" do
    record = Document.new(document_type: "act")
    assert_not record.valid?
    assert record.errors[:source_key].any?
    assert record.errors[:name].any?
  end

  test "accepts supported document types only" do
    %w[act decree guide].each do |type|
      @document.document_type = type
      assert @document.valid?
    end
    @document.document_type = "unknown"
    assert_not @document.valid?
    assert @document.errors[:document_type].any?
  end

  test "rejects duplicate source keys" do
    record = Document.new(source_key: @document.source_key, name: "중복 문서", document_type: "act")
    assert_not record.valid?
    assert record.errors[:source_key].any?
  end

  test "stores law effective date as a date" do
    @document.update!(law_effective_date: "2026-09-11")
    assert_equal Date.new(2026, 9, 11), @document.reload.law_effective_date
  end

  test "destroy removes its chunks and preserves other documents" do
    other = Document.create!(source_key: "test_privacy_decree", name: "시행령", document_type: "decree")
    chunk = @document.document_chunks.create!(chunk_id: "act:제1조:1", position: 1, part_index: 1, part_count: 1,
      article_number: "제1조", text: "본문", embedding: embedding)
    other_chunk = other.document_chunks.create!(chunk_id: "decree:제1조:1", position: 1, part_index: 1, part_count: 1,
      article_number: "제1조", text: "시행령 본문", embedding: embedding)

    @document.destroy!

    assert_not Document.exists?(@document.id)
    assert_not DocumentChunk.exists?(chunk.id)
    assert Document.exists?(other.id)
    assert DocumentChunk.exists?(other_chunk.id)
  end
end
