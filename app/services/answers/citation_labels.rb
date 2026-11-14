module Answers
  # 근거 조문의 제목·상태 문구. 프롬프트(Answers::Generate::Citation)와 화면(AnswerCitation)이 같은 문구를 쓴다.
  # document_name, article_number, article_title, part_index, part_count, status, effective_date,
  # pending_amendment_date를 가진 객체에 include한다.
  module CitationLabels
    def pending? = status.to_s == "pending"
    def amended? = !pending? && pending_amendment_date.present?
    def partial? = part_count.to_i > 1

    # 예: "개인정보 보호법 제21조(개인정보의 파기)"
    def heading
      title = article_title.present? ? "(#{article_title})" : ""
      "#{document_name} #{article_number}#{title}"
    end

    def part_label = partial? ? "일부 #{part_index}/#{part_count}" : nil

    def status_label
      return "시행 전 · #{effective_date.iso8601} 시행" if pending?
      return "현행 · #{pending_amendment_date.iso8601} 개정 예정" if amended?

      "현행"
    end
  end
end
