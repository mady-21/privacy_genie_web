module AnswersHelper
  LIST_ITEM = /\A[-*•]\s+/

  # 같은 페이지 앵커를 Turbo가 pushState로 처리하면 :target 강조가 갱신되지 않으므로 브라우저 기본 이동을 쓴다.
  CITATION_LINK_DATA = { turbo: false }.freeze

  # 답변 본문을 문단·목록으로 나누고 [n]을 근거 조문 카드 링크로 바꾼다. 본문은 모두 이스케이프한다.
  def answer_body(text)
    blocks = text.to_s.strip.split(/\n\s*\n/)
    safe_join(blocks.map { |block| answer_block(block) })
  end

  # 현행(초록), 개정 예정·시행 전(노랑) 배지
  def citation_badge(citation)
    kind, hook =
      if citation.pending? then [ :warning, "badge-pending" ]
      elsif citation.amended? then [ :warning, "badge-amended" ]
      else [ :success, "badge-effective" ]
      end
    badge_tag(citation.status_label, kind, hook: hook)
  end

  # 안내 문구 안의 "[n]" 링크
  def citation_link(citation)
    link_to("[#{citation.number}]", "#citation-#{citation.number}", class: UiHelper::CITE, data: CITATION_LINK_DATA)
  end

  PROGRESS_STEPS = [
    [ "searching", "관련 조문을 찾고 있습니다" ],
    [ "generating", "조문을 근거로 답변을 쓰고 있습니다" ]
  ].freeze

  # 진행 단계 상태별 [글자, 점] 클래스
  PROGRESS_STATE_CLASSES = {
    "done" => [ "text-stone-600 dark:text-stone-400", "border-blue-600 bg-blue-600 dark:border-blue-400 dark:bg-blue-400" ],
    "current" => [ "font-semibold", "border-blue-600 motion-safe:animate-pulse dark:border-blue-400" ],
    "todo" => [ "text-stone-500 dark:text-stone-500", "border-stone-300 dark:border-stone-600" ]
  }.freeze

  # 진행 단계 목록의 각 항목 상태: done, current, todo
  def progress_steps(answer)
    current = answer.pending? ? 0 : PROGRESS_STEPS.index { |status, _| status == answer.status }.to_i
    PROGRESS_STEPS.each_with_index.map do |(_, label), index|
      state = index < current ? "done" : (index == current ? "current" : "todo")
      [ label, state ]
    end
  end

  private

  # 한 덩어리 안에서 "- "로 시작하는 줄은 목록으로, 나머지 줄은 문단(줄바꿈 유지)으로 묶는다.
  def answer_block(block)
    groups = block.lines.map(&:strip).reject(&:empty?).chunk_while { |a, b| a.match?(LIST_ITEM) == b.match?(LIST_ITEM) }
    safe_join(groups.map do |lines|
      if lines.first.match?(LIST_ITEM)
        tag.ul(class: "mb-3 list-disc space-y-1 pl-5") { safe_join(lines.map { |line| tag.li(with_citation_links(line.sub(LIST_ITEM, ""))) }) }
      else
        tag.p(safe_join(lines.map { |line| with_citation_links(line) }, tag.br), class: "mb-3")
      end
    end)
  end

  def with_citation_links(line)
    parts = line.split(/(\[\d+\])/)
    safe_join(parts.map do |part|
      if (number = part[/\A\[(\d+)\]\z/, 1])
        link_to(number, "#citation-#{number}", class: UiHelper::CITE, aria: { label: "근거 조문 #{number}" }, data: CITATION_LINK_DATA)
      else
        part
      end
    end)
  end
end
