module PrivacyGenieDoc
  class Client
    def initialize(
      base_url: ENV.fetch("PRIVACY_GENIE_DOC_URL")
    )
      @connection = Faraday.new(url: base_url)
    end

    def health
      response = @connection.get("/health")

      unless response.success?
        raise "privacy-genie-doc API error: #{response.status}"
      end

      JSON.parse(response.body)
    end
  end
end