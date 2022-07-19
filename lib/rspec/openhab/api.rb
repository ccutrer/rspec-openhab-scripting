# frozen_string_literal: true

require "faraday"

module OpenHAB
  class API
    def initialize(url, token = nil)
      @faraday = Faraday.new(url) do |f|
        f.response :raise_error
        f.response :json
        f.path_prefix = "/rest/"
        f.headers = { "X-OPENHAB-TOKEN" => token } if token
      end
    end

    def version
      version = root_data.dig("runtimeInfo", "version")
      version = "#{version}-SNAPSHOT" if root_data.dig("runtimeInfo", "buildString")&.start_with?("Build #")
      version
    end

    def locale
      root_data["locale"]
    end

    def measurement_system
      root_data["measurementSystem"]
    end

    def items
      @faraday.get("items", metadata: ".*").body
    end

    def item(name)
      @faraday.get("items/#{name}").body
    rescue Faraday::ResourceNotFound
      nil
    end

    def channel_types
      @faraday.get("channel-types").body
    end

    def thing_types
      @faraday.get("thing-types").body
    end

    def things
      @faraday.get("things").body
    end

    def authenticated?
      @faraday.headers.key?("X-OPENHAB-TOKEN")
    end

    private

    def root_data
      @root_data ||= @faraday.get.body
    end
  end
end
