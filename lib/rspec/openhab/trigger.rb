# frozen_string_literal: true

module RSpec
  module OpenHAB
    module Trigger
      def trigger_rule(rule_name, event = nil)
        @rules ||= ::OpenHAB::DSL::Rules::Rule.script_rules.each_with_object({}) { |r, obj| obj[r.name] = r }

        @rules.fetch(rule_name).execute(nil, { "event" => event })
      end
    end
  end
end

RSpec.configure do |config|
  config.include RSpec::OpenHAB::Trigger
end
