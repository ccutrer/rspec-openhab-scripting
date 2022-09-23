# frozen_string_literal: true

module OpenHAB
  module Transform
    class << self
      def add_script(modules, script)
        full_name = modules.join("/")
        name = modules.pop
        (@scripts ||= {})[full_name] = engine_factory.script_engine.compile(script)

        mod = modules.inject(self) { |m, n| m.const_get(n, false) }
        mod.singleton_class.define_method(name) do |input, **kwargs|
          Transform.send(:transform, full_name, input, kwargs)
        end
      end

      private

      def engine_factory
        @engine_factory ||= org.jruby.embed.jsr223.JRubyEngineFactory.new
      end

      def transform(name, input, kwargs)
        script = @scripts[name]
        ctx = script.engine.context
        ctx.set_attribute("input", input.to_s, javax.script.ScriptContext::ENGINE_SCOPE)
        kwargs.each do |(k, v)|
          ctx.set_attribute(k.to_s, v.to_s, javax.script.ScriptContext::ENGINE_SCOPE)
        end
        script.eval
      end
    end
  end
end

module RSpec
  module OpenHAB
    module Helpers
      module BindingHelper
        def add_kwargs_to_current_binding(binding, kwargs)
          kwargs.each { |(k, v)| binding.local_variable_set(k, v) }
        end
      end

      private_constant :BindingHelper

      singleton_class.include(Helpers)

      def autoupdate_all_items
        if instance_variable_defined?(:@autoupdated_items)
          raise RuntimeError "you should only call `autoupdate_all_items` once per spec"
        end

        @autoupdated_items = []

        $ir.for_each do |_provider, item|
          if item.meta.key?("autoupdate")
            @autoupdated_items << item.meta.delete("autoupdate")
            item.meta["autoupdate"] = true
          end
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

      def autorequires
        requires = jrubyscripting_config&.get("require") || ""
        requires.split(",").each do |f|
          require f.strip
        end
      end

      def launch_karaf(include_bindings: true,
                       include_jsondb: true,
                       private_confdir: false,
                       use_root_instance: false)
        karaf = RSpec::OpenHAB::Karaf.new("#{Dir.pwd}/.karaf")
        karaf.include_bindings = include_bindings
        karaf.include_jsondb = include_jsondb
        karaf.private_confdir = private_confdir
        karaf.use_root_instance = use_root_instance
        main = karaf.launch

        ENV["RUBYLIB"] ||= ""
        ENV["RUBYLIB"] += ":" unless ENV["RUBYLIB"].empty?
        ENV["RUBYLIB"] += rubylib_dir
        require "openhab"
        require "rspec/openhab/core/logger"

        require "rspec/openhab/core/mocks/persistence_service"

        # override several openhab-scripting methods
        require_relative "actions"
        require_relative "core/item_proxy"
        require_relative "dsl/timers/timer"
        # TODO: still needed?
        require_relative "dsl/rules/triggers/watch"

        ps = RSpec::OpenHAB::Core::Mocks::PersistenceService.instance
        bundle = org.osgi.framework.FrameworkUtil.get_bundle(org.openhab.core.persistence.PersistenceService)
        bundle.bundle_context.register_service(org.openhab.core.persistence.PersistenceService.java_class, ps, nil)

        # wait for the rule engine
        rs = ::OpenHAB::Core::OSGI.service("org.openhab.core.service.ReadyService")
        filter = org.openhab.core.service.ReadyMarkerFilter.new
                    .with_type(org.openhab.core.service.StartLevelService::STARTLEVEL_MARKER_TYPE)
                    .with_identifier(org.openhab.core.service.StartLevelService::STARTLEVEL_RULEENGINE.to_s)

        karaf.send(:wait) do |continue|
          rs.register_tracker(org.openhab.core.service.ReadyService::ReadyTracker.impl { continue.call }, filter)
        end

        # RSpec additions
        require "rspec/openhab/suspend_rules"

        if ::RSpec.respond_to?(:config)
          ::RSpec.configure do |config|
            config.include OpenHAB::Core::EntityLookup
          end
        end
        main
      rescue Exception => e
        puts e.inspect
        puts e.backtrace
        raise
      end

      def load_rules
        automation_path = "#{org.openhab.core.OpenHAB.config_folder}/automation/jsr223/ruby/personal"

        RSpec::OpenHAB::SuspendRules.suspend_rules do
          Dir["#{automation_path}/*.rb"].each do |f|
            load f
          rescue Exception => e
            warn "Failed loading #{f}: #{e.inspect}"
            warn e.backtrace
          end
        end
      end

      def load_transforms
        transform_path = "#{org.openhab.core.OpenHAB.config_folder}/transform"
        Dir["#{transform_path}/**/*.script"].each do |filename|
          script = File.read(filename)
          next unless ruby_file?(script)

          filename.slice!(0..transform_path.length)
          dir = File.dirname(filename)
          modules = (dir == ".") ? [] : moduleize(dir)
          basename = File.basename(filename)
          method = basename[0...-7]
          modules << method
          ::OpenHAB::Transform.add_script(modules, script)
        end
      end

      private

      def jrubyscripting_config
        ca = ::OpenHAB::Core::OSGI.service("org.osgi.service.cm.ConfigurationAdmin")
        ca.get_configuration("org.openhab.automation.jrubyscripting", nil)&.properties
      end

      def rubylib_dir
        jrubyscripting_config&.get("rubylib") || "#{org.openhab.core.OpenHAB.config_folder}/automation/lib/ruby"
      end

      EMACS_MODELINE_REGEXP = /# -\*-(.+)-\*-/.freeze

      def parse_emacs_modeline(line)
        line[EMACS_MODELINE_REGEXP, 1]
            &.split(";")
            &.map(&:strip)
            &.map { |l| l.split(":", 2).map(&:strip).tap { |a| a[1] ||= nil } }
            &.to_h
      end

      def ruby_file?(script)
        # check the first 1KB for an emacs magic comment
        script[0..1024].split("\n").any? { |line| parse_emacs_modeline(line)&.dig("mode") == "ruby" }
      end

      def moduleize(term)
        term
          .sub(/^[a-z\d]*/, &:capitalize)
          .gsub(%r{(?:_|(/))([a-z\d]*)}) { "#{$1}#{$2.capitalize}" }
          .split("/")
      end

      # need to transfer autoupdate metadata from GenericMetadataProvider to ManagedMetadataProvider
      # so that we can mutate it in the future
      def set_up_autoupdates
        gmp = ::OpenHAB::Core::OSGI.service("org.openhab.core.model.item.internal.GenericMetadataProvider")
        mr = ::OpenHAB::Core::OSGI.service("org.openhab.core.items.MetadataRegistry")
        mmp = mr.managed_provider.get
        to_add = []
        gmp.all.each do |metadata|
          next unless metadata.uid.namespace == "autoupdate"

          to_add << metadata
        end
        gmp.remove_metadata_by_namespace("autoupdate")

        to_add.each do |m|
          if mmp.get(m.uid)
            mmp.update(m)
          else
            mmp.add(m)
          end
        end
      end

      def restore_autoupdate_items
        return unless instance_variable_defined?(:@autoupdated_items)

        mr = ::OpenHAB::Core::OSGI.service("org.openhab.core.items.MetadataRegistry")
        @autoupdated_items&.each do |meta|
          mr.update(meta)
        end
        @autoupdated_items = nil
      end
    end

    if RSpec.respond_to?(:configure)
      RSpec.configure do |config|
        config.include Helpers
      end
    end
  end
end
