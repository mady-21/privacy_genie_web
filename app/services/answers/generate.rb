module Answers
  # 질문 하나에 답한다: 조문 검색 → 조문 원문에 [1][2] 번호를 붙여 프롬프트 조립 → LLM 호출 → 인용 번호 검증.
  # 저장은 하지 않는다(호출하는 Job이 Answer에 기록한다). 질문은 이미 Answers::Masking을 거친 것이어야 한다.
  # 검색·LLM 에러(Documents::Search::ModelMismatch, PrivacyGenieDoc::Client::Error, Llm::Error)는 그대로 올린다.
  class Generate
    SEARCH_LIMIT = 5
    # 가장 가까운 조문의 유사도가 이보다 낮으면 LLM을 부르지 않고 "근거 없음"으로 끝낸다.
    # 2026-11-14 실측: 평가셋 30문항의 최저값 0.481, 무관한 질문(날씨·요리·주식·코딩) 0.32~0.42,
    # 다른 법 분야(퇴직금·전세·이혼) 0.45 안팎. 경계에 걸린 질문은 LLM이 NO_BASIS_MARKER로 판정한다.
    MIN_SIMILARITY = 0.43
    MAX_TOKENS = 2048
    NO_BASIS_MARKER = "근거 없음".freeze
    OUTCOMES = %i[answered no_basis truncated refused].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      당신은 한국의 개인정보 보호법과 같은 법 시행령을 근거로 질문에 답하는 도우미입니다.

      규칙
      1. <근거 조문>에 있는 내용만 근거로 답합니다. 조문에 없는 내용은 추측하지 말고 "제공된 조문으로는 확인할 수 없습니다"라고 씁니다.
      2. 문장마다 근거가 된 조문 번호를 [1], [2]처럼 대괄호 숫자로 붙입니다. 여러 개면 [1][3]처럼 이어 씁니다. 목록에 없는 번호는 쓰지 않습니다.
      3. "시행 전"으로 표시된 조문을 인용할 때는 아직 시행되지 않았다는 점과 시행일을 밝히고, 현행 조문과 구분해 설명합니다.
      4. "개정 예정"으로 표시된 조문은 현행 내용으로 답하고, 개정 예정일이 있다는 점을 덧붙입니다.
      5. 근거 조문이 질문과 관련이 없어 답할 수 없으면 다른 말 없이 "#{NO_BASIS_MARKER}"이라고만 씁니다.
      6. 짧은 문단과 "- "로 시작하는 목록만 씁니다. 제목, 표, 굵은 글씨, 링크는 쓰지 않습니다.
      7. 법률 자문이 아닌 일반적인 법령 정보로서 답합니다. 질문자의 구체적 사실관계를 단정하지 않습니다.
    PROMPT

    # 근거 조문 한 개. number는 프롬프트의 [n]과 같고, cited는 답변이 실제로 인용했는지다.
    Citation = Data.define(
      :number, :cited, :document_type, :document_name, :article_number, :article_title, :chapter,
      :part_index, :part_count, :text, :status, :effective_date, :pending_amendment_date, :similarity
    ) do
      include CitationLabels

      def self.from_search(number, result)
        chunk = result.chunk
        new(
          number: number, cited: false,
          document_type: chunk.document.document_type, document_name: chunk.document.name,
          article_number: chunk.article_number, article_title: chunk.article_title, chapter: chunk.chapter,
          part_index: chunk.part_index, part_count: chunk.part_count, text: chunk.text,
          status: result.status, effective_date: result.effective_date,
          pending_amendment_date: result.pending_amendment_date, similarity: result.similarity
        )
      end
    end

    # outcome: OUTCOMES 중 하나. body: [n]이 든 답변(없는 번호는 지운 상태). citations: 검색된 조문 전체.
    # dropped_citation_numbers: LLM이 만들어 낸, 목록에 없는 번호. llm: Llm::Response(LLM을 안 불렀으면 nil).
    Result = Data.define(:outcome, :body, :citations, :dropped_citation_numbers, :llm) do
      def cited_citations = citations.select(&:cited)
    end

    CITATION_MARK = /([ \t]*)\[(\d+(?:\s*[,，]\s*\d+)*)\]/

    # llm: 테스트에서 가짜 provider를 넣는 자리. 생략하면 provider 플래그(nil이면 LLM_PROVIDER)로 고른다.
    def initialize(search: Documents::Search.new, provider: nil, llm: nil)
      @search = search
      @provider = provider
      @llm = llm
    end

    # on_progress: LLM을 부르기 직전에 (:generating, citations)로 불린다. LLM이 실패해도 근거 조문을 남길 수 있다.
    def call(question, on_progress: nil)
      results = @search.call(question, limit: SEARCH_LIMIT)
      citations = results.each_with_index.map { |result, index| Citation.from_search(index + 1, result) }
      if citations.empty? || citations.map(&:similarity).max < MIN_SIMILARITY
        return Result.new(outcome: :no_basis, body: nil, citations: citations, dropped_citation_numbers: [], llm: nil)
      end

      on_progress&.call(:generating, citations)
      response = (@llm || Llm.provider(@provider)).generate(
        messages: [ Llm::Message.user(prompt(question, citations)) ],
        system: SYSTEM_PROMPT,
        max_tokens: MAX_TOKENS
      )
      build_result(response, citations)
    end

    private

    def prompt(question, citations)
      sources = citations.map do |citation|
        label = [ citation.status_label, citation.part_label ].compact.join(", ")
        "[#{citation.number}] #{citation.heading} — #{label}\n#{citation.text}"
      end
      "<근거 조문>\n#{sources.join("\n\n")}\n</근거 조문>\n\n<질문>\n#{question}\n</질문>"
    end

    def build_result(response, citations)
      text = response.text.to_s.strip
      if response.refused? || text.start_with?(NO_BASIS_MARKER) || text.empty?
        outcome = response.refused? ? :refused : :no_basis
        return Result.new(outcome: outcome, body: nil, citations: citations, dropped_citation_numbers: [], llm: response)
      end

      # 잘린 답변 끝에 남은 "[1" 같은 조각은 지운다.
      text = text.sub(/\[[\d,\s]*\z/, "").rstrip if response.truncated?
      body, used, dropped = check_citations(text, citations.size)
      Result.new(
        outcome: response.truncated? ? :truncated : :answered,
        body: body,
        citations: citations.map { |citation| citation.with(cited: used.include?(citation.number)) },
        dropped_citation_numbers: dropped.uniq,
        llm: response
      )
    end

    # [1, 2]는 [1][2]로 풀고, 목록에 없는 번호는 지운다. 표시가 통째로 사라지면 앞 공백도 함께 지운다.
    def check_citations(text, count)
      used = []
      dropped = []
      body = text.gsub(CITATION_MARK) do
        space = Regexp.last_match(1)
        numbers = Regexp.last_match(2).split(/\s*[,，]\s*/).map(&:to_i)
        valid, invalid = numbers.uniq.partition { |number| number.between?(1, count) }
        used.concat(valid)
        dropped.concat(invalid)
        valid.empty? ? "" : space + valid.map { |number| "[#{number}]" }.join
      end
      [ body, used.uniq, dropped ]
    end
  end
end
