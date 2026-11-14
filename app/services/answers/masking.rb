module Answers
  # 질문에 섞인 개인정보를 정규식으로 찾아 [전화번호] 같은 자리표시로 바꾼다.
  # 임베딩(doc)·LLM 전송과 저장보다 먼저 거친다. 이름·주소처럼 형식이 없는 정보는 잡지 못하므로 화면 안내로 보완한다.
  module Masking
    Result = Data.define(:text, :kinds) do
      def masked? = kinds.any?
    end

    # 위에서부터 차례로 바꾼다. 숫자 앞뒤에 다른 숫자가 붙어 있으면 더 긴 번호의 일부이므로 건드리지 않는다.
    RULES = [
      [ "이메일", /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/ ],
      # 주민등록번호·외국인등록번호: 생년월일 6자리 + 1~8로 시작하는 7자리
      [ "주민등록번호", /(?<!\d)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\s*-?\s*[1-8]\d{6}(?!\d)/ ],
      [ "카드번호", /(?<!\d)\d{4}(?:[\s-]?\d{4}){3}(?!\d)/ ],
      [ "전화번호", /(?<!\d)(?:01[016789]|0[2-6]\d?|070|080)[\s-]?\d{3,4}[\s-]?\d{4}(?!\d)/ ],
      # 계좌번호: 하이픈으로 나뉜 3~4덩이, 숫자 10~16자리. 날짜(2026-11-14)는 8자리라 걸리지 않는다.
      [ "계좌번호", /(?<!\d)\d{2,6}(?:-\d{2,8}){2,3}(?!\d)/, ->(match) { match.count("0-9").between?(10, 16) } ]
    ].freeze

    def self.call(text)
      kinds = []
      masked = RULES.reduce(text.to_s) do |current, (kind, pattern, condition)|
        current.gsub(pattern) do |match|
          next match if condition && !condition.call(match)

          kinds << kind unless kinds.include?(kind)
          "[#{kind}]"
        end
      end
      Result.new(text: masked, kinds: kinds)
    end
  end
end
