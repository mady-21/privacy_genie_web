require "test_helper"

class Documents::EvaluationTest < ActiveSupport::TestCase
  Evaluation = Documents::Evaluation

  setup do
    @act = Document.create!(source_key: "privacy", name: "개인정보 보호법", document_type: "act", embedding_model: FakeDocClient::MODEL)
    @decree = Document.create!(source_key: "privacy_decree", name: "개인정보 보호법 시행령", document_type: "decree",
      embedding_model: FakeDocClient::MODEL)
    # 모든 질문은 0번 축 벡터다. 청크는 다른 축 가중치(distance)가 클수록 질문에서 멀어진다.
    @client = FakeDocClient.new(embeddings: [ "질문", "질문 하나", "질문 둘" ].index_with { embedding(0 => 1) })
  end

  test "ranks the first chunk of the answer article, ignoring part and occurrence" do
    create_chunk(@act, "제1조", distance: 1)
    create_chunk(@act, "제2조", distance: 2, part_index: 2, part_count: 2, chunk_id: "act:제2조:2:part2")
    create_chunk(@act, "제2조", distance: 3, part_index: 1, part_count: 2, chunk_id: "act:제2조:2:part1")

    assert_equal 2, evaluate(question(answers: [ answer("act", "제2조") ])).rank
  end

  test "uses the best rank among several answers" do
    create_chunk(@act, "제1조", distance: 1)
    create_chunk(@decree, "제5조", distance: 2)
    create_chunk(@act, "제3조", distance: 3)

    assert_equal 2, evaluate(question(answers: [ answer("act", "제3조"), answer("decree", "제5조") ])).rank
  end

  test "the document type is part of the answer" do
    create_chunk(@act, "제1조", distance: 1)
    create_chunk(@decree, "제1조", distance: 2)

    assert_equal 2, evaluate(question(answers: [ answer("decree", "제1조") ])).rank
  end

  test "counts ranks beyond top_k so MRR reflects the whole ranking" do
    6.times { |index| create_chunk(@act, "제#{index + 1}조", distance: index + 1) }
    create_chunk(@act, "제7조", distance: 7)

    result = evaluate(question(answers: [ answer("act", "제7조") ]))

    assert_equal 7, result.rank
    assert_not result.hit?(5)
    assert_in_delta 1.0 / 7, result.reciprocal_rank, 1e-9
  end

  test "effective rank skips pending chunks only for questions that require it" do
    create_chunk(@act, "제2조", distance: 1, is_effective: false, article_effective_date: Date.new(2027, 3, 9), text: "개정될 본문")
    create_chunk(@act, "제1조", distance: 2)
    create_chunk(@act, "제2조", distance: 3, text: "현행 본문")

    strict = evaluate(question(answers: [ answer("act", "제2조") ], require_effective: true), top_k: 2)
    assert_equal [ 1, 3 ], [ strict.rank, strict.effective_rank ]
    assert strict.hit?(2)
    assert_not strict.effective_hit?(2)
    assert strict.missed?(2)

    loose = evaluate(question(answers: [ answer("act", "제2조") ]), top_k: 2)
    assert_nil loose.effective_rank
    assert_not loose.missed?(2)
  end

  test "a pending part identical to its current part does not take a rank" do
    # 검색이 글자가 같은 미시행본을 빼므로, 그 뒤 조문의 순위가 밀리지 않아야 한다.
    create_chunk(@act, "제75조", distance: 1, text: "제75조(과태료) 첫 조각")
    create_chunk(@act, "제75조", distance: 1, text: "제75조(과태료) 첫 조각", is_effective: false,
      article_effective_date: Date.new(2027, 7, 1))
    create_chunk(@act, "제76조", distance: 2)

    assert_equal 2, evaluate(question(answers: [ answer("act", "제76조") ])).rank
  end

  test "an answer that is not loaded is missed with a zero reciprocal rank" do
    create_chunk(@act, "제1조", distance: 1)

    result = evaluate(question(answers: [ answer("act", "제99조") ]))

    assert_nil result.rank
    assert_equal 0.0, result.reciprocal_rank
    assert result.missed?(5)
  end

  test "does not call the doc service when no chunks are loaded" do
    result = evaluate(question)

    assert_nil result.rank
    assert_empty @client.embed_requests
  end

  test "keeps the top chunks for explaining misses" do
    3.times { |index| create_chunk(@act, "제#{index + 1}조", distance: index + 1) }

    result = evaluate(question(answers: [ answer("act", "제3조") ]), top_k: 2)

    assert_equal %w[제1조 제2조], result.top_chunks.map(&:article_number)
  end

  test "searches each question once with the question text" do
    create_chunk(@act, "제1조", distance: 1)

    report = Evaluation.new(search: search, eval_set: eval_set(question(id: "G1", text: "질문 하나"), question(id: "G2", text: "질문 둘"))).call

    assert_equal [ [ "질문 하나" ], [ "질문 둘" ] ], @client.embed_requests
    assert_equal %w[G1 G2], report.results.map { |result| result.question.id }
  end

  private

  def evaluate(question, top_k: 5)
    Evaluation.new(search: search, eval_set: eval_set(question, top_k: top_k)).call.results.sole
  end

  def search = Documents::Search.new(client: @client)

  def eval_set(*questions, top_k: 5) = Evaluation::EvalSet.new(top_k: top_k, questions: questions)

  def answer(document_type, article_number) = Evaluation::Answer.new(document_type, article_number)

  def question(id: "Q1", category: "general", text: "질문", answers: [ answer("act", "제1조") ], require_effective: false)
    Evaluation::Question.new(id: id, category: category, text: text, answers: answers, require_effective: require_effective, note: nil)
  end

  def create_chunk(document, article_number, distance:, text: nil, part_index: 1, part_count: 1, chunk_id: nil, **attributes)
    @sequence = (@sequence || 0) + 1
    @positions = (@positions || Hash.new(0)).tap { |positions| positions[document.id] += 1 }
    document.document_chunks.create!(
      chunk_id: chunk_id || "#{document.source_key}:#{article_number}:#{@sequence}",
      position: @positions[document.id],
      article_number: article_number,
      text: text || "#{article_number} 본문 #{@sequence}",
      part_index: part_index,
      part_count: part_count,
      # 청크마다 다른 축을 써서 질문과의 거리가 distance 순서대로 정해지게 한다.
      embedding: embedding(0 => 1, @sequence => distance),
      **attributes
    )
  end
end

class Documents::EvaluationReportTest < ActiveSupport::TestCase
  Evaluation = Documents::Evaluation

  setup do
    act = Document.create!(source_key: "privacy", name: "개인정보 보호법", document_type: "act", embedding_model: FakeDocClient::MODEL)
    noise = act.document_chunks.create!(chunk_id: "noise", position: 1, article_number: "제62조의3", text: "본문",
      part_index: 1, part_count: 1, embedding: embedding)
    # 손으로 계산할 수 있게 순위를 직접 정한다: 1위, 4위, 못 찾음, 6위(현행 7위).
    @report = Evaluation::Report.new(top_k: 5, results: [
      result("G1", "general", rank: 1),
      result("G2", "general", rank: 4),
      result("G3", "general", rank: nil, top_chunks: [ noise ]),
      result("F1", "fine", rank: 6, effective_rank: 7, require_effective: true, top_chunks: [ noise ])
    ])
  end

  test "recall and MRR over all questions" do
    assert_in_delta 2.0 / 4, @report.recall, 1e-9
    assert_in_delta (1 + 1.0 / 4 + 0 + 1.0 / 6) / 4, @report.mrr, 1e-9
  end

  test "per category scores" do
    categories = @report.by_category

    assert_equal %w[general fine], categories.keys
    assert_in_delta 2.0 / 3, @report.recall(categories["general"]), 1e-9
    assert_in_delta (1 + 1.0 / 4) / 3, @report.mrr(categories["general"]), 1e-9
    assert_equal 0.0, @report.recall(categories["fine"])
  end

  test "effective hit rate counts only questions that require it" do
    assert_equal 0.0, @report.effective_hit_rate
    assert_equal %w[F1], @report.effective_results.map { |result| result.question.id }
    assert_nil Evaluation::Report.new(top_k: 5, results: [ result("G1", "general", rank: 1) ]).effective_hit_rate
  end

  test "misses are questions outside top_k" do
    assert_equal %w[G3 F1], @report.misses.map { |result| result.question.id }
  end

  test "lines summarize scores and explain misses" do
    lines = @report.lines

    assert_equal "전체 Recall@5 0.500  MRR 0.354  (4문항)", lines[0]
    assert_equal "일반 Recall@5 0.667  MRR 0.417  (3문항)", lines[1]
    assert_equal "과태료 Recall@5 0.000  MRR 0.167  (1문항)", lines[2]
    assert_equal "현행 적중률@5 0.000 (1문항)", lines[3]
    assert_equal "놓친 문항:", lines[4]
    assert_equal "  G3 G3 질문 | 정답 법 제1조, 순위 - | 상위: 법 제62조의3", lines[5]
    assert_equal "  F1 F1 질문 | 정답 법 제1조, 순위 6, 현행 순위 7 | 상위: 법 제62조의3", lines[6]
  end

  test "lines say so when nothing is missed" do
    report = Evaluation::Report.new(top_k: 5, results: [ result("G1", "general", rank: 1) ])

    assert_equal "놓친 문항 없음", report.lines.last
  end

  test "to_h keeps scores and per question ranks for saving" do
    hash = @report.to_h

    assert_equal 5, hash[:top_k]
    assert_in_delta 0.5, hash[:recall], 1e-9
    assert_equal({ count: 1, recall: 0.0, mrr: 1.0 / 6 }, hash[:categories]["fine"])
    assert_equal({ id: "F1", rank: 6, effective_rank: 7, missed: true }, hash[:results].last)
  end

  private

  def result(id, category, rank:, effective_rank: nil, require_effective: false, top_chunks: [])
    question = Evaluation::Question.new(id: id, category: category, text: "#{id} 질문",
      answers: [ Evaluation::Answer.new("act", "제1조") ], require_effective: require_effective, note: nil)
    Evaluation::QuestionResult.new(question: question, rank: rank, effective_rank: effective_rank, top_chunks: top_chunks)
  end
end
