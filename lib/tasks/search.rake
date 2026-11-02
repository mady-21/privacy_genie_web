namespace :search do
  desc "검색 평가셋으로 실제 검색 품질을 잽니다 (OUTPUT=결과.json, MIN_RECALL=0.8이면 기준 미달 시 실패)"
  task evaluate: :environment do
    report = Documents::Evaluation.new.call
    puts report.lines

    if ENV["OUTPUT"].present?
      path = Pathname(ENV["OUTPUT"])
      path.dirname.mkpath
      path.write(JSON.pretty_generate(report.to_h))
      puts "결과 저장: #{path}"
    end

    if ENV["MIN_RECALL"].present?
      minimum = Float(ENV["MIN_RECALL"])
      abort format("Recall@%d %.3f가 기준 %.3f보다 낮습니다", report.top_k, report.recall, minimum) if report.recall < minimum
    end
  rescue Documents::Evaluation::InvalidEvalSet, Documents::Search::ModelMismatch, PrivacyGenieDoc::Client::Error => error
    abort "검색 평가 실패 - #{error.class}: #{error.message}"
  end
end
