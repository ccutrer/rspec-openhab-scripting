# frozen_string_literal: true

module OpenHAB
  module DSL
    module Rules
      class RuleConfig
        # override on_start to never work
        def on_start?
          false
        end
      end
    end
  end
end
