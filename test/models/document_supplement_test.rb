require "test_helper"

class DocumentSupplementTest < ActiveSupport::TestCase
  setup do
    @document = Document.create!(source_key: "test_privacy_act", name: "법률", document_type: "act")
    @other = Document.create!(source_key: "test_privacy_decree", name: "시행령", document_type: "decree")
    @supplement = @document.document_supplements.create!(source_key: "supplement-1", heading: "부칙")
  end

  test "requires document source key and heading" do
    record = DocumentSupplement.new
    assert_not record.valid?
    %i[document source_key heading].each { |field| assert record.errors[field].any? }
  end

  test "source key is unique within a document" do
    duplicate = @document.document_supplements.build(source_key: "supplement-1", heading: "부칙")
    assert_not duplicate.valid?
    assert duplicate.errors[:source_key].any?
    assert @other.document_supplements.build(source_key: "supplement-1", heading: "부칙").valid?
  end

  test "preamble must be an array of strings including an empty array" do
    [ [], [ "이 법은 공포한 날부터 시행한다." ] ].each do |value|
      @supplement.preamble = value
      assert @supplement.valid?
    end
    [ nil, {}, "본문", [ 1 ] ].each do |value|
      @supplement.preamble = value
      assert_not @supplement.valid?
      assert @supplement.errors[:preamble].any?
    end
  end

  test "cannot destroy a supplement with chunks" do
    add_chunk
    assert_raises(ActiveRecord::DeleteRestrictionError) { @supplement.destroy! }
    assert DocumentSupplement.exists?(@supplement.id)
  end

  test "cannot change document while chunks exist" do
    chunk = add_chunk
    @supplement.document = @other
    assert_not @supplement.save
    assert @supplement.errors[:document].any?
    assert_equal @document.id, @supplement.reload.document_id
    assert_equal @document.id, chunk.reload.document_id
  end

  test "can destroy a supplement without chunks" do
    @supplement.destroy!
    assert_not DocumentSupplement.exists?(@supplement.id)
    assert Document.exists?(@document.id)
  end

  private

  def add_chunk
    @document.document_chunks.create!(position: 1, article_number: "제1조", text: "부칙 본문", document_supplement: @supplement)
  end
end
