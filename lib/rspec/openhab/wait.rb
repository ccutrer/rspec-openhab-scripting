# frozen_string_literal: true

module RSpec
  module OpenHAB
    module Wait
      def wait_for_rules
        loop do
          sleep(0.1)
          break if java.lang.Thread.all_stack_traces.keys.all? do |t|
                     !t.name.match?(/^OH-rule-/) ||
                     [java.lang.Thread::State::WAITING, java.lang.Thread::State::TIMED_WAITING].include?(t.state)
                   end
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.include RSpec::OpenHAB::Wait
end
