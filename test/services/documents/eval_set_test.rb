require "test_helper"

class Documents::EvalSetTest < ActiveSupport::TestCase
  EvalSet = Documents::Evaluation::EvalSet

  test "the bundled eval set has the documented composition" do
    eval_set = EvalSet.load

    assert_equal 5, eval_set.top_k
    assert_equal 30, eval_set.questions.size
    assert_equal 30, eval_set.questions.map(&:id).uniq.size
    assert_equal({ "general" => 23, "fine" => 7 }, eval_set.questions.map(&:category).tally)
    assert_equal %w[F1 F2 F3 F4 F5 F6 F7 G11 G22].sort,
      eval_set.questions.select(&:require_effective).map(&:id).sort
    assert eval_set.questions.flat_map(&:answers).all? { |answer| %w[act decree].include?(answer.document_type) }
  end

  test "questions keep their answers in order" do
    g6 = EvalSet.load.questions.find { |question| question.id == "G6" }

    assert_equal [ [ "act", "제22조의2" ], [ "decree", "제17조의2" ] ], g6.answers.map { |answer| [ answer.document_type, answer.article_number ] }
    assert_equal [ "법 제22조의2", "령 제17조의2" ], g6.answers.map(&:label)
  end

  test "rejects malformed question fields with the reason" do
    cases = {
      "question이 없습니다" => { "question" => " " },
      "category가 general/fine가 아닙니다" => { "category" => "other" },
      "answers가 비어 있습니다" => { "answers" => [] },
      "answers는 document_type" => { "answers" => [ { "document_type" => "guide", "article_number" => "제1조" } ] },
      "require_effective는 true/false여야 합니다" => { "require_effective" => "yes" },
      "id가 없습니다" => { "id" => nil }
    }
    cases.each do |reason, override|
      error = assert_raises(Documents::Evaluation::InvalidEvalSet, reason) { load_data(questions: [ question(**override) ]) }
      assert_includes error.message, reason
    end
  end

  test "rejects duplicate ids, a bad top_k and an empty question list" do
    assert_includes load_error(questions: [ question, question ]).message, "id가 중복됩니다: Q1"
    assert_includes load_error(top_k: 0, questions: [ question ]).message, "top_k는 1 이상의 정수여야 합니다"
    assert_includes load_error(questions: []).message, "questions가 비어 있습니다"
  end

  test "rejects a file that is not JSON" do
    with_file("{ not json") do |path|
      error = assert_raises(Documents::Evaluation::InvalidEvalSet) { EvalSet.load(path) }
      assert_includes error.message, "JSON이 아닙니다"
    end
  end

  private

  def question(**override)
    {
      "id" => "Q1", "category" => "general", "question" => "질문",
      "answers" => [ { "document_type" => "act", "article_number" => "제1조" } ],
      "require_effective" => false, "note" => ""
    }.merge(override.transform_keys(&:to_s))
  end

  def load_data(top_k: 5, questions:)
    with_file(JSON.generate("top_k" => top_k, "questions" => questions)) { |path| EvalSet.load(path) }
  end

  def load_error(**data)
    assert_raises(Documents::Evaluation::InvalidEvalSet) { load_data(**data) }
  end

  def with_file(content)
    Tempfile.create([ "eval_set", ".json" ]) do |file|
      file.write(content)
      file.flush
      yield file.path
    end
  end
end
