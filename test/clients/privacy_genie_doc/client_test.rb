require "test_helper"

class PrivacyGenieDoc::ClientTest < ActiveSupport::TestCase
  setup do
    @stubs = Faraday::Adapter::Test::Stubs.new
    connection = Faraday.new(url: "http://privacy-genie-doc:8000") { |faraday| faraday.adapter :test, @stubs }
    @client = PrivacyGenieDoc::Client.new(base_url: "http://privacy-genie-doc:8000", connection: connection)
  end

  test "document fetches chunks and vectors of a document type" do
    body = { "source_key" => "privacy", "document_type" => "act", "chunks" => [] }
    @stubs.get("/documents/act") { [ 200, json_headers, JSON.generate(body) ] }

    assert_equal body, @client.document("act")
    @stubs.verify_stubbed_calls
  end

  test "embed posts texts as JSON" do
    @stubs.post("/embeddings") do |env|
      assert_equal "application/json", env.request_headers["Content-Type"]
      assert_equal({ "texts" => [ "질문" ] }, JSON.parse(env.body))
      [ 200, json_headers, JSON.generate("model" => "m", "dimension" => 2, "embeddings" => [ [ 1.0, 0.0 ] ]) ]
    end

    assert_equal [ [ 1.0, 0.0 ] ], @client.embed([ "질문" ])["embeddings"]
  end

  test "503 raises service unavailable with the detail" do
    @stubs.get("/documents/act") { [ 503, json_headers, JSON.generate("detail" => "rebuild를 다시 하세요") ] }

    error = assert_raises(PrivacyGenieDoc::Client::ServiceUnavailable) { @client.document("act") }
    assert_includes error.message, "503"
    assert_includes error.message, "rebuild를 다시 하세요"
  end

  test "422 raises invalid request" do
    @stubs.get("/documents/guide") { [ 422, json_headers, JSON.generate("detail" => [ { "msg" => "invalid" } ]) ] }

    assert_raises(PrivacyGenieDoc::Client::InvalidRequest) { @client.document("guide") }
  end

  test "other failures raise the base error" do
    @stubs.get("/health") { [ 500, {}, "Internal Server Error" ] }
    @stubs.get("/documents/act") { raise Faraday::ConnectionFailed, "connection refused" }

    assert_raises(PrivacyGenieDoc::Client::Error) { @client.health }
    error = assert_raises(PrivacyGenieDoc::Client::Error) { @client.document("act") }
    assert_includes error.message, "connection refused"
  end

  private

  def json_headers
    { "Content-Type" => "application/json" }
  end
end
