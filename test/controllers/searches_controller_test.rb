require "test_helper"

class SearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @act = Document.create!(source_key: "privacy", name: "개인정보 보호법", document_type: "act", embedding_model: FakeDocClient::MODEL)
    @decree = Document.create!(source_key: "privacy_decree", name: "개인정보 보호법 시행령", document_type: "decree",
      embedding_model: FakeDocClient::MODEL)
    @client = FakeDocClient.new(embeddings: { "질문" => embedding(0 => 1) })
    @original_factory = SearchesController.search_factory
    use_client(@client)
  end

  teardown do
    SearchesController.search_factory = @original_factory
  end

  test "a blank question shows only the form without calling doc" do
    get search_path, params: { q: "   " }

    assert_response :success
    assert_select "form.search-form[method=get] textarea[name=q]"
    assert_select "form.search-form input[type=submit][name]", count: 0
    assert_select ".search-results", count: 0
    assert_empty @client.embed_requests
  end

  test "shows results nearest first with labels, parts, status and text" do
    far = create_chunk(@decree, "제16조", distance: 3, article_title: "개인정보의 파기방법")
    near = create_chunk(@act, "제21조", distance: 1, article_title: "개인정보의 파기", chapter: "제3장 개인정보의 처리",
      part_index: 1, part_count: 2, text: "제21조(개인정보의 파기) 본문")

    get search_path, params: { q: "질문" }

    assert_response :success
    assert_equal [ [ "질문" ] ], @client.embed_requests
    assert_select ".search-result", 2
    assert_select ".search-result:nth-child(1)#document_chunk_#{near.id} h2", /법 제21조\(개인정보의 파기\)\s+조각 1\/2/
    assert_select ".search-result:nth-child(1) .search-meta", /유사도 0\.707.*현행.*제3장 개인정보의 처리/m
    assert_select ".search-result:nth-child(1) .search-text", "제21조(개인정보의 파기) 본문"
    assert_select ".search-result:nth-child(2)#document_chunk_#{far.id} h2", /령 제16조\(개인정보의 파기방법\)/
    assert_select ".search-result:nth-child(2) h2 small", count: 0
  end

  test "marks pending chunks and current chunks with a pending amendment" do
    create_chunk(@act, "제2조", distance: 1, text: "현행 정의")
    create_chunk(@act, "제2조", distance: 2, text: "개정될 정의", is_effective: false, article_effective_date: Date.new(2027, 3, 9))

    get search_path, params: { q: "질문" }

    assert_select ".search-result:nth-child(1) .search-status-effective", "현행 · 개정 예정 2027-03-09"
    assert_select ".search-result:nth-child(2) .search-status-pending", "미시행 (2027-03-09 시행)"
  end

  test "effective only leaves out pending chunks" do
    current = create_chunk(@act, "제1조", distance: 2)
    create_chunk(@act, "제2조", distance: 1, is_effective: false, article_effective_date: Date.new(2027, 3, 9))

    get search_path, params: { q: "질문", effective_only: "1" }

    assert_select ".search-result", 1
    assert_select "#document_chunk_#{current.id}"
    assert_select "input[name=effective_only][checked]"
  end

  test "limit is clamped to 1..20" do
    21.times { |index| create_chunk(@act, "제#{index + 1}조", distance: index + 1) }

    get search_path, params: { q: "질문", limit: "0" }
    assert_select ".search-result", 1
    assert_select "input[name=limit][value='1']"

    get search_path, params: { q: "질문", limit: "999" }
    assert_select ".search-result", 20
    assert_select "input[name=limit][value='20']"
  end

  test "a too long question is rejected without calling doc" do
    get search_path, params: { q: "가" * (SearchesController::MAX_QUESTION_LENGTH + 1) }

    assert_response :unprocessable_content
    assert_select ".search-error", /10,000자까지/
    assert_empty @client.embed_requests
  end

  test "a question at the length limit is searched" do
    long_question = "가" * SearchesController::MAX_QUESTION_LENGTH
    @client.embeddings[long_question] = embedding(0 => 1)

    get search_path, params: { q: long_question }

    assert_response :success
    assert_equal [ [ long_question ] ], @client.embed_requests
  end

  test "says when nothing is loaded" do
    get search_path, params: { q: "질문" }

    assert_response :success
    assert_select ".search-empty", /documents:sync/
  end

  test "doc errors become a 503 with the reason" do
    failing = Class.new(FakeDocClient) do
      def embed(_texts) = raise(PrivacyGenieDoc::Client::ServiceUnavailable, "privacy-genie-doc API error: 503")
    end.new
    use_client(failing)

    get search_path, params: { q: "질문" }

    assert_response :service_unavailable
    assert_select ".search-error", /privacy-genie-doc에 연결할 수 없습니다.*503/
  end

  test "a model mismatch asks for a resync" do
    create_chunk(@act, "제1조", distance: 1)
    @client.model = "other/model"

    get search_path, params: { q: "질문" }

    assert_response :service_unavailable
    assert_select ".search-error", /documents:sync로 다시 동기화하세요/
  end

  test "chunk text is escaped" do
    create_chunk(@act, "제1조", distance: 1, text: "<script>alert(1)</script>")

    get search_path, params: { q: "질문" }

    assert_select ".search-text script", count: 0
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  private

  def use_client(client)
    SearchesController.search_factory = -> { Documents::Search.new(client: client) }
  end

  def create_chunk(document, article_number, distance:, text: nil, part_index: 1, part_count: 1, **attributes)
    @sequence = (@sequence || 0) + 1
    document.document_chunks.create!(
      chunk_id: "#{document.source_key}:#{article_number}:#{@sequence}",
      position: @sequence,
      article_number: article_number,
      text: text || "#{article_number} 본문",
      part_index: part_index,
      part_count: part_count,
      embedding: embedding(0 => 1, @sequence => distance),
      **attributes
    )
  end
end
