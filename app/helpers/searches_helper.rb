module SearchesHelper
  def document_label(document)
    document.document_type == "act" ? "법" : "령"
  end

  def search_status_label(result)
    return "미시행 (#{result.effective_date.iso8601} 시행)" if result.status == :pending
    return "현행 · 개정 예정 #{result.pending_amendment_date.iso8601}" if result.pending_amendment_date

    "현행"
  end
end
