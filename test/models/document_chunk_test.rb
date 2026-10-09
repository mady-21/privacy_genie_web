require "test_helper"

class DocumentChunkTest < ActiveSupport::TestCase
  setup do
    @document = Document.create!(source_key: "test_privacy_act", name: "법률", document_type: "act")
    @other = Document.create!(source_key: "test_privacy_decree", name: "시행령", document_type: "decree")
    @supplement = @document.document_supplements.create!(source_key: "supplement-1", heading: "부칙")
    @chunk = @document.document_chunks.build(position: 1, article_number: "제1조", text: "본문")
  end

  test "requires document article number and nonblank text" do
    @chunk.document = nil
    @chunk.article_number = ""
    @chunk.text = " \n "
    assert_not @chunk.valid?
    %i[document article_number text].each { |field| assert @chunk.errors[field].any? }
  end

  test "position must be a positive integer" do
    [ nil, 0, -1, 1.5 ].each do |value|
      @chunk.position = value
      assert_not @chunk.valid?
      assert @chunk.errors[:position].any?
    end
  end

  test "position is unique within a document" do
    @chunk.save!
    duplicate = @document.document_chunks.build(position: 1, article_number: "제2조", text: "본문")
    assert_not duplicate.valid?
    assert duplicate.errors[:position].any?
    assert @other.document_chunks.build(position: 1, article_number: "제1조", text: "본문").valid?
  end

  test "metadata accepts an object and rejects other JSON types" do
    [ {}, { "created" => "본조신설" } ].each do |value|
      @chunk.metadata = value
      assert @chunk.valid?
    end
    [ nil, [], "메타데이터" ].each do |value|
      @chunk.metadata = value
      assert_not @chunk.valid?
      assert @chunk.errors[:metadata].any?
    end
  end

  test "allows main body or a supplement of the same document" do
    assert @chunk.valid?
    @chunk.document_supplement = @supplement
    assert @chunk.valid?
  end

  test "rejects a supplement from another document" do
    foreign_supplement = @other.document_supplements.create!(source_key: "supplement-1", heading: "부칙")
    @chunk.document_supplement = foreign_supplement
    assert_not @chunk.valid?
    assert @chunk.errors[:document_supplement].any?
  end

  test "does not treat two different unsaved documents as the same document" do
    first = Document.new(source_key: "new-act", name: "법률", document_type: "act")
    second = Document.new(source_key: "new-decree", name: "시행령", document_type: "decree")
    @chunk.document = first
    @chunk.document_supplement = second.document_supplements.build(source_key: "supplement-1", heading: "부칙")
    assert_not @chunk.valid?
    assert @chunk.errors[:document_supplement].any?
  end

  test "scopes separate main and supplement chunks and order them" do
    extra = @document.document_chunks.create!(position: 2, article_number: "제1조", text: "부칙 본문", document_supplement: @supplement)
    @chunk.save!
    assert_equal [ @chunk.id ], @document.document_chunks.main_body.pluck(:id)
    assert_equal [ extra.id ], @document.document_chunks.supplementary.pluck(:id)
    assert_equal [ @chunk.id, extra.id ], @document.document_chunks.ordered.pluck(:id)
  end
end
