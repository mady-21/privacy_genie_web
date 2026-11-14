module Llm
  # 대화 한 턴. 시스템 지시는 메시지가 아니라 generate의 system:으로 넘긴다(provider마다 위치가 다르다).
  class Message < Data.define(:role, :content)
    ROLES = %i[user assistant].freeze

    def self.user(content) = new(role: :user, content: content)
    def self.assistant(content) = new(role: :assistant, content: content)

    def initialize(role:, content:)
      role = role.to_sym
      raise ArgumentError, "role은 #{ROLES.join(', ')} 중 하나여야 합니다: #{role}" unless ROLES.include?(role)
      raise ArgumentError, "content가 비어 있습니다" if content.to_s.strip.empty?

      super(role: role, content: content.to_s)
    end
  end
end
