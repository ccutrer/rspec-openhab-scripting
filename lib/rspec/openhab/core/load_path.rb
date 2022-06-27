# frozen_string_literal: true

module OpenHAB
  module Core
    OPENHAB_SHARE_PATH = "#{org.openhab.core.OpenHAB.config_folder}/automation/lib/ruby"

    class << self
      def add_rubylib_to_load_path
        $LOAD_PATH.unshift(OPENHAB_SHARE_PATH) unless $LOAD_PATH.include?(OPENHAB_SHARE_PATH)
      end
end
  end
end
