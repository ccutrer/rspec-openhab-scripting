# frozen_string_literal: true

module RSpec
  module OpenHAB
    module Wait
      def execute_timers
        OpenHAB::DSL::Timers.timer_manager.execute_timers
      end
    end
  end
end

RSpec.configure do |config|
  config.include RSpec::OpenHAB::Wait
end
