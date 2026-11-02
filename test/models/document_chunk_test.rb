require "test_helper"

class DocumentChunkTest < ActiveSupport::TestCase
  setup do
    @document = Document.create!(source_key: "test_privacy_act", name: "법률", document_type: "act")
    @other = Document.create!(source_key: "test_privacy_decree", name: "시행령", document_type: "decree")
    @chunk = build_chunk(@document, chunk_id: "act:제1조:1", position: 1)
  end

  test "requires document chunk id article number nonblank text and embedding" do
    @chunk.document = nil
    @chunk.chunk_id = ""
    @chunk.article_number = ""
    @chunk.text = " \n "
    @chunk.embedding = nil
    assert_not @chunk.valid?
    %i[document chunk_id article_number text embedding].each { |field| assert @chunk.errors[field].any?, field }
  end

  test "chunk id is unique across documents" do
    @chunk.save!
    duplicate = build_chunk(@other, chunk_id: @chunk.chunk_id, position: 1)
    assert_not duplicate.valid?
    assert duplicate.errors[:chunk_id].any?
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
    duplicate = build_chunk(@document, chunk_id: "act:제2조:1", position: 1)
    assert_not duplicate.valid?
    assert duplicate.errors[:position].any?
    assert build_chunk(@other, chunk_id: "decree:제1조:1", position: 1).valid?
  end

  test "part index must be within part count" do
    @chunk.part_index = 2
    @chunk.part_count = 3
    assert @chunk.valid?

    @chunk.part_index = 4
    assert_not @chunk.valid?
    assert @chunk.errors[:part_index].any?

    [ nil, 0 ].each do |value|
      @chunk.part_count = value
      assert_not @chunk.valid?
      assert @chunk.errors[:part_count].any?
    end
  end

  test "pending chunks need an article effective date" do
    @chunk.is_effective = false
    assert_not @chunk.valid?
    assert @chunk.errors[:article_effective_date].any?

    @chunk.article_effective_date = Date.new(2027, 7, 1)
    assert @chunk.valid?
  end

  test "database rejects a pending chunk without an effective date" do
    @chunk.save!
    assert_raises(ActiveRecord::StatementInvalid) do
      DocumentChunk.transaction(requires_new: true) do
        @chunk.update_columns(is_effective: false, article_effective_date: nil)
      end
    end
  end

  test "embedding must have 1024 dimensions" do
    @chunk.embedding = [ 1.0, 0.0 ]
    assert_not @chunk.valid?
    assert @chunk.errors[:embedding].any?
  end

  test "embedding round trips through the vector column" do
    vector = embedding(0 => 3, 5 => 4)
    @chunk.embedding = vector
    @chunk.save!
    assert_equal DocumentChunk::EMBEDDING_DIMENSION, @chunk.reload.embedding.size
    assert_in_delta 0.6, @chunk.embedding[0], 1e-6
    assert_in_delta 0.8, @chunk.embedding[5], 1e-6
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

  test "scopes split effective and pending chunks and order them" do
    pending = build_chunk(@document, chunk_id: "act:제1조:2", position: 2,
      is_effective: false, article_effective_date: Date.new(2027, 7, 1))
    pending.save!
    @chunk.save!
    assert_equal [ @chunk.id ], @document.document_chunks.effective.pluck(:id)
    assert_equal [ pending.id ], @document.document_chunks.pending.pluck(:id)
    assert_equal [ @chunk.id, pending.id ], @document.document_chunks.ordered.pluck(:id)
  end

  private

  def build_chunk(document, **attributes)
    document.document_chunks.build(
      part_index: 1, part_count: 1, article_number: "제1조", text: "본문", embedding: embedding, **attributes
    )
  end
end
