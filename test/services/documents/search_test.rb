require "test_helper"

class Documents::SearchTest < ActiveSupport::TestCase
  setup do
    @act = Document.create!(source_key: "privacy", name: "개인정보 보호법", document_type: "act", embedding_model: FakeDocClient::MODEL)
    @decree = Document.create!(source_key: "privacy_decree", name: "개인정보 보호법 시행령", document_type: "decree",
      embedding_model: FakeDocClient::MODEL)
    @client = FakeDocClient.new(embeddings: { "질문" => embedding(0 => 1) })
    @search = Documents::Search.new(client: @client)
  end

  test "returns the nearest chunks by cosine distance" do
    far = create_chunk(@act, "제3조", embedding(0 => 1, 1 => 3))
    near = create_chunk(@act, "제1조", embedding(0 => 1))
    middle = create_chunk(@decree, "제2조", embedding(0 => 1, 1 => 1))

    results = @search.call("질문", limit: 3)

    assert_equal [ [ "질문" ] ], @client.embed_requests
    assert_equal [ near, middle, far ], results.map(&:chunk)
    assert_in_delta 0.0, results[0].distance, 1e-6
    assert_in_delta 1 - Math.sqrt(0.5), results[1].distance, 1e-6
    assert_in_delta Math.sqrt(0.5), results[1].similarity, 1e-6
    assert_equal :effective, results[0].status
  end

  test "respects the limit" do
    6.times { |index| create_chunk(@act, "제#{index + 1}조", embedding(0 => 1, index + 1 => index + 1)) }

    assert_equal 2, @search.call("질문", limit: 2).size
  end

  test "keeps pending chunks and marks them" do
    pending = create_chunk(@act, "제2조", embedding(0 => 1), text: "개정될 본문",
      is_effective: false, article_effective_date: Date.new(2027, 3, 9))

    result = @search.call("질문").sole

    assert_equal pending, result.chunk
    assert_equal :pending, result.status
    assert_equal Date.new(2027, 3, 9), result.effective_date
    assert_nil result.pending_amendment_date
  end

  test "effective only leaves out pending chunks" do
    create_chunk(@act, "제2조", embedding(0 => 1), is_effective: false, article_effective_date: Date.new(2027, 3, 9))
    current = create_chunk(@act, "제1조", embedding(0 => 1, 1 => 1))

    assert_equal [ current ], @search.call("질문", effective_only: true).map(&:chunk)
  end

  test "drops a pending part identical to its current part and keeps the amendment date" do
    # 제75조처럼 현행본·미시행본의 같은 조각이 글자까지 같으면 하나만 남긴다. 다른 조각은 둘 다 남긴다.
    current_first = create_chunk(@act, "제75조", embedding(0 => 1), text: "제75조(과태료) 첫 조각", part_index: 1, part_count: 2)
    create_chunk(@act, "제75조", embedding(0 => 1), text: "제75조(과태료) 첫 조각", part_index: 1, part_count: 2,
      is_effective: false, article_effective_date: Date.new(2027, 7, 1))
    current_second = create_chunk(@act, "제75조", embedding(0 => 1, 1 => 1), text: "현행 제2항", part_index: 2, part_count: 2)
    pending_second = create_chunk(@act, "제75조", embedding(0 => 1, 1 => 1.1), text: "개정 제2항", part_index: 2, part_count: 2,
      is_effective: false, article_effective_date: Date.new(2027, 7, 1))

    results = @search.call("질문")

    assert_equal [ current_first, current_second, pending_second ], results.map(&:chunk)
    assert_equal [ Date.new(2027, 7, 1), Date.new(2027, 7, 1), nil ], results.map(&:pending_amendment_date)
  end

  test "identical text in another article or document is not merged" do
    create_chunk(@act, "제1조", embedding(0 => 1), text: "같은 본문")
    create_chunk(@decree, "제1조", embedding(0 => 1), text: "같은 본문",
      is_effective: false, article_effective_date: Date.new(2027, 2, 20))

    assert_equal [ :effective, :pending ], @search.call("질문").map(&:status).sort
  end

  test "leaves out documents loaded with another embedding model" do
    current = create_chunk(@act, "제1조", embedding(0 => 1, 1 => 1))
    create_chunk(@decree, "제1조", embedding(0 => 1))
    @decree.update!(embedding_model: "old/model")

    assert_equal [ current ], @search.call("질문").map(&:chunk)
  end

  test "raises when no document matches the question model" do
    create_chunk(@act, "제1조", embedding(0 => 1))
    @client.model = "other/model"

    error = assert_raises(Documents::Search::ModelMismatch) { @search.call("질문") }
    assert_includes error.message, "privacy"
  end

  test "returns nothing when no chunks are loaded" do
    assert_empty @search.call("질문")
  end

  private

  def create_chunk(document, article_number, vector, text: nil, part_index: 1, part_count: 1, **attributes)
    @positions = (@positions || Hash.new(0)).tap { |positions| positions[document.id] += 1 }
    position = @positions[document.id]
    document.document_chunks.create!(
      chunk_id: "#{document.source_key}:#{article_number}:#{position}",
      position: position,
      article_number: article_number,
      text: text || "#{article_number} 본문 #{position}",
      part_index: part_index,
      part_count: part_count,
      embedding: vector,
      **attributes
    )
  end
end
