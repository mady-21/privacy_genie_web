namespace :documents do
  desc "privacy-genie-doc에서 청크와 벡터를 받아 DB에 맞춥니다 (TYPE=act|decree, 생략하면 둘 다)"
  task sync: :environment do
    document_types = ENV["TYPE"].present? ? [ ENV["TYPE"] ] : Documents::Sync::DOCUMENT_TYPES
    sync = Documents::Sync.new

    # 문서마다 트랜잭션이 따로라서, 하나가 실패해도 앞서 성공한 문서는 커밋된 채로 남는다.
    failures = document_types.filter_map do |document_type|
      result = sync.call(document_type)
      puts "#{document_type}(#{result.source_key}): 추가 #{result.inserted}, 삭제 #{result.deleted}, " \
        "유지 #{result.kept}#{', 임베딩 모델이 바뀌어 전체 재적재' if result.reloaded}"
      nil
    rescue Documents::Sync::InvalidPayload, PrivacyGenieDoc::Client::Error, ActiveRecord::ActiveRecordError => error
      warn "#{document_type}: 실패 - #{error.class}: #{error.message}"
      document_type
    end

    abort "동기화 실패: #{failures.join(', ')}" if failures.any?
  end
end
