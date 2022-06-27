# frozen_string_literal: true

module OpenHAB
  module Core
    module ScriptHandling
      module_function

      def script_loaded(&block); end
      def script_unloaded(&block); end
    end

    module ScriptHandlingCallbacks
    end
  end

  module DSL
    module Core
      ScriptHandling = OpenHAB::Core::ScriptHandling
    end
  end
end
