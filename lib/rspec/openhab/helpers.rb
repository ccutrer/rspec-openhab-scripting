# frozen_string_literal: true

module RSpec
  module OpenHAB
    module Helpers
      def autoupdate_all_items
        @autoupdated_items ||= {}
        $ir.for_each do |_provider, item|
          @autoupdated_items[item] = item.meta.delete("autoupdate") if item.meta.key?("autoupdate")
        end
      end

      def execute_timers
        ::OpenHAB::DSL::Timers.timer_manager.execute_timers
      end

      def suspend_rules(&block)
        SuspendRules.suspend_rules(&block)
      end

      def trigger_rule(rule_name, event = nil)
        @rules ||= ::OpenHAB::DSL::Rules::Rule.script_rules.each_with_object({}) { |r, obj| obj[r.name] = r }

        @rules.fetch(rule_name).execute(nil, { "event" => event })
      end

      def trigger_channel(channel, event)
        channel = org.openhab.core.thing.ChannelUID.new(channel) if channel.is_a?(String)
        channel = channel.uid if channel.is_a?(org.openhab.core.thing.Channel)
        thing = channel.thing
        thing.handler.callback.channel_triggered(nil, channel, event)
      end

      private

      def restore_autoupdate_items
        return unless instance_variable_defined?(:@autoupdated_items)

        @autoupdated_items.each do |(item, meta)|
          item.meta["autoupdate"] = meta
        end
      end
    end

    RSpec.configure do |config|
      config.include Helpers
    end
  end
end
