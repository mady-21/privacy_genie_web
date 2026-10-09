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

  test "destroy removes its chunks before supplements and preserves other documents" do
    other = Document.create!(source_key: "test_privacy_decree", name: "시행령", document_type: "decree")
    supplement = @document.document_supplements.create!(source_key: "supplement-1", heading: "부칙")
    main = @document.document_chunks.create!(position: 1, article_number: "제1조", text: "본문")
    extra = @document.document_chunks.create!(position: 2, article_number: "제1조", text: "부칙 본문", document_supplement: supplement)
    other_chunk = other.document_chunks.create!(position: 1, article_number: "제1조", text: "시행령 본문")

    @document.destroy!

    assert_not Document.exists?(@document.id)
    assert_not DocumentSupplement.exists?(supplement.id)
    assert_not DocumentChunk.where(id: [ main.id, extra.id ]).exists?
    assert Document.exists?(other.id)
    assert DocumentChunk.exists?(other_chunk.id)
  end
end
