module Documents
  # 검색 평가셋(config/evaluation/retrieval_eval_v1.json)으로 Documents::Search의 품질을 잰다.
  # 적중 판정은 평가셋 정의를 따른다: 검색된 청크의 문서 종류·조번호가 정답 조문과 같으면 적중이고,
  # 조각(part)·occurrence는 무시한다. 정답이 여러 조문이면 하나만 맞아도 적중이다.
  class Evaluation
    DEFAULT_PATH = Rails.root.join("config/evaluation/retrieval_eval_v1.json")
    CATEGORIES = { "general" => "일반", "fine" => "과태료" }.freeze
    DOCUMENT_LABELS = { "act" => "법", "decree" => "령" }.freeze

    class InvalidEvalSet < StandardError; end

    Answer = Data.define(:document_type, :article_number) do
      def match?(chunk) = chunk.document.document_type == document_type && chunk.article_number == article_number
      def label = "#{DOCUMENT_LABELS.fetch(document_type)} #{article_number}"
    end

    Question = Data.define(:id, :category, :text, :answers, :require_effective, :note) do
      def answer?(chunk) = answers.any? { |answer| answer.match?(chunk) }
    end

    EvalSet = Data.define(:top_k, :questions) do
      def self.load(path = DEFAULT_PATH)
        data = JSON.parse(File.read(path))
        errors = validate(data)
        raise InvalidEvalSet, "#{path}: #{errors.join(', ')}" if errors.any?

        new(top_k: data["top_k"], questions: data["questions"].map { |question| build_question(question) })
      rescue JSON::ParserError => error
        raise InvalidEvalSet, "#{path}: JSON이 아닙니다 (#{error.message})"
      end

      def self.validate(data)
        return [ "최상위가 JSON 객체가 아닙니다" ] unless data.is_a?(Hash)

        errors = []
        errors << "top_k는 1 이상의 정수여야 합니다" unless data["top_k"].is_a?(Integer) && data["top_k"].positive?
        questions = data["questions"]
        return errors << "questions가 비어 있습니다" if !questions.is_a?(Array) || questions.empty?

        questions.each_with_index { |question, index| errors.concat(question_errors(question, index)) }
        duplicates = questions.filter_map { |question| question["id"] if question.is_a?(Hash) }.tally.select { |_, count| count > 1 }.keys
        errors << "id가 중복됩니다: #{duplicates.join(', ')}" if duplicates.any?
        errors
      end

      def self.question_errors(question, index)
        return [ "#{index + 1}번째 문항이 객체가 아닙니다" ] unless question.is_a?(Hash)

        name = question["id"].presence || "#{index + 1}번째 문항"
        errors = []
        errors << "#{name}: id가 없습니다" if question["id"].blank?
        errors << "#{name}: question이 없습니다" if question["question"].blank?
        errors << "#{name}: category가 #{CATEGORIES.keys.join('/')}가 아닙니다" unless CATEGORIES.key?(question["category"])
        errors << "#{name}: require_effective는 true/false여야 합니다" unless [ true, false ].include?(question["require_effective"])
        answers = question["answers"]
        if !answers.is_a?(Array) || answers.empty?
          errors << "#{name}: answers가 비어 있습니다"
        elsif answers.any? { |answer| !valid_answer?(answer) }
          errors << "#{name}: answers는 document_type(#{DOCUMENT_LABELS.keys.join('/')})과 article_number가 있어야 합니다"
        end
        errors
      end

      def self.valid_answer?(answer)
        answer.is_a?(Hash) && DOCUMENT_LABELS.key?(answer["document_type"]) && answer["article_number"].present?
      end

      def self.build_question(question)
        Question.new(
          id: question["id"],
          category: question["category"],
          text: question["question"],
          answers: question["answers"].map { |answer| Answer.new(answer["document_type"], answer["article_number"]) },
          require_effective: question["require_effective"],
          note: question["note"]
        )
      end
    end

    # rank: 정답 조문이 처음 나온 순위(1부터, 없으면 nil). effective_rank: require_effective 문항에서 현행 청크 기준 순위.
    QuestionResult = Data.define(:question, :rank, :effective_rank, :top_chunks) do
      def hit?(top_k) = rank.present? && rank <= top_k
      def effective_hit?(top_k) = effective_rank.present? && effective_rank <= top_k
      def reciprocal_rank = rank ? 1.0 / rank : 0.0
      def missed?(top_k) = !hit?(top_k) || (question.require_effective && !effective_hit?(top_k))
    end

    Report = Data.define(:top_k, :results) do
      def recall(scope = results) = scope.count { |result| result.hit?(top_k) }.fdiv(scope.size)
      def mrr(scope = results) = scope.sum(&:reciprocal_rank) / scope.size

      def by_category
        CATEGORIES.keys.filter_map do |category|
          scope = results.select { |result| result.question.category == category }
          [ category, scope ] if scope.any?
        end.to_h
      end

      def effective_results = results.select { |result| result.question.require_effective }

      def effective_hit_rate
        scope = effective_results
        scope.empty? ? nil : scope.count { |result| result.effective_hit?(top_k) }.fdiv(scope.size)
      end

      def misses = results.select { |result| result.missed?(top_k) }

      def lines
        lines = [ summary_line("전체", results) ]
        by_category.each { |category, scope| lines << summary_line(CATEGORIES.fetch(category), scope) }
        if (rate = effective_hit_rate)
          lines << format("현행 적중률@%d %.3f (%d문항)", top_k, rate, effective_results.size)
        end
        return lines << "놓친 문항 없음" if misses.empty?

        lines << "놓친 문항:"
        misses.each { |result| lines << miss_line(result) }
        lines
      end

      def to_h
        {
          top_k: top_k,
          recall: recall,
          mrr: mrr,
          effective_hit_rate: effective_hit_rate,
          categories: by_category.transform_values { |scope| { count: scope.size, recall: recall(scope), mrr: mrr(scope) } },
          results: results.map do |result|
            { id: result.question.id, rank: result.rank, effective_rank: result.effective_rank, missed: result.missed?(top_k) }
          end
        }
      end

      private

      def summary_line(label, scope)
        format("%s Recall@%d %.3f  MRR %.3f  (%d문항)", label, top_k, recall(scope), mrr(scope), scope.size)
      end

      def miss_line(result)
        question = result.question
        effective = question.require_effective ? ", 현행 순위 #{result.effective_rank || '-'}" : ""
        top = result.top_chunks.map { |chunk| "#{DOCUMENT_LABELS.fetch(chunk.document.document_type)} #{chunk.article_number}" }
        "  #{question.id} #{question.text} | 정답 #{question.answers.map(&:label).join(', ')}, " \
          "순위 #{result.rank || '-'}#{effective} | 상위: #{top.join(', ')}"
      end
    end

    def initialize(search: Documents::Search.new, eval_set: EvalSet.load)
      @search = search
      @eval_set = eval_set
    end

    def call
      depth = DocumentChunk.count
      results = @eval_set.questions.map do |question|
        # MRR을 전체 순위로 계산하려고 적재된 청크 전부를 순위대로 받는다(청크가 수백 개라 부담이 없다).
        ranked = depth.zero? ? [] : @search.call(question.text, limit: depth).map(&:chunk)
        QuestionResult.new(
          question: question,
          rank: first_rank(ranked) { |chunk| question.answer?(chunk) },
          effective_rank: (first_rank(ranked) { |chunk| chunk.is_effective && question.answer?(chunk) } if question.require_effective),
          top_chunks: ranked.first(@eval_set.top_k)
        )
      end
      Report.new(top_k: @eval_set.top_k, results: results)
    end

    private

    def first_rank(chunks)
      index = chunks.index { |chunk| yield chunk }
      index && index + 1
    end
  end
end
