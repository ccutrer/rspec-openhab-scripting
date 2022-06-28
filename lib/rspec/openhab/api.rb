# frozen_string_literal: true

require "faraday_middleware"

module OpenHAB
  class API
    def initialize(url)
      @faraday = Faraday.new(url) do |f|
        f.request :retry
        f.response :raise_error
        f.response :json
        f.adapter :net_http_persistent
        f.path_prefix = "/rest/"
      end
    end

    def version
      body = @faraday.get.body
      version = body.dig("runtimeInfo", "version")
      version = "#{version}-SNAPSHOT" if body.dig("runtimeInfo", "buildString")&.start_with?("Build #")
      version
    end

    def items
      @faraday.get("items").body
    end

    def item(name)
      @faraday.get("items/#{name}").body
    rescue Faraday::ResourceNotFound
      nil
    end
  end
end
