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

      def autorequires
        ca = ::OpenHAB::Core::OSGI.service(org.osgi.service.cm.ConfigurationAdmin)
        requires = ca.get_configuration("org.openhab.automation.jrubyscripting")&.properties&.get("require") || ""
        requires.split(",").each do |f|
          require f.trim
        end
      end

      def populate_items_from_api
        api = ::OpenHAB::DSL::Imports.api
        all_items = api.items

        item_factory = org.openhab.core.library.CoreItemFactory.new

        all_items.each do |item_json|
          full_type = item_json["type"]
          name = item_json["name"]

          type, _dimension = full_type.split(":")
          if type == "Group"
            base_item = item_factory.create_item(item_json["groupType"], name) if item_json["groupType"]
            if item_json["function"]
              dto = org.openhab.core.items.dto.GroupFunctionDTO.new
              dto.name = item_json.dig("function", "name")
              dto.params = item_json.dig("function", "params")
              function = org.openhab.core.items.dto.ItemDTOMapper.map_function(base_item, dto)
            end
            item = GroupItem.new(name, base_item, function)
          else
            item = item_factory.create_item(full_type, name)
          end

          item.label = item_json["label"]
          item_json["tags"].each do |tag|
            item.add_tag(tag)
          end
          item_json["metadata"]&.each do |key, config|
            item.meta[key] = config["value"], config["config"]
          end
          item.meta["stateDescription"] = item_json["stateDescription"] if item_json["stateDescription"]
          item.category = item_json["category"] if item_json["category"]

          $ir.add(item)

          next unless item.meta["channel"]&.value

          channel_uid = org.openhab.core.thing.ChannelUID.new(item.meta["channel"].value)
          channel = $things.get_channel(channel_uid)
          next unless channel

          link = org.openhab.core.thing.link.ItemChannelLink.new(item.name, channel_uid)
          Core::Mocks::ItemChannelLinkProvider.instance.add(link)
        end
        all_items.each do |item_json| # rubocop:disable Style/CombinableLoops
          item_json["groupNames"].each do |group_name|
            next unless (group = $ir.get(group_name))

            group.add_member($ir.get(item_json["name"]))
          end
        end
      end

      def populate_things_from_api
        api = ::OpenHAB::DSL::Imports.api
        populate_channel_types_from_api(api)
        populate_thing_types_from_api(api)

        thing_type_registry = ::OpenHAB::Core::OSGI.service("org.openhab.core.thing.type.ThingTypeRegistry")

        api.things.each do |thing_json|
          uid = org.openhab.core.thing.ThingUID.new(thing_json["UID"])
          type_uid = org.openhab.core.thing.ThingTypeUID.new(thing_json["thingTypeUID"])
          bridge_uid = org.openhab.core.thing.ThingUID.new(thing_json["bridgeUID"]) if thing_json["bridgeUID"]

          type = thing_type_registry.get_thing_type(type_uid)
          klass = if type.is_a?(org.openhab.core.thing.type.BridgeType)
                    org.openhab.core.thing.binding.builder.BridgeBuilder
                  else
                    org.openhab.core.thing.binding.builder.ThingBuilder
                  end
          builder = klass.create(type_uid, uid)
          builder.with_bridge(bridge_uid) if bridge_uid

          thing_json.each do |(k, v)|
            case k
            when "UID", "thingTypeUID", "bridgeUID", "statusInfo", "editable"
              nil
            when "channels"
              builder.with_channels(v.map { |c| build_channel(c) })
            when "configuration"
              builder.with_configuration(org.openhab.core.config.core.Configuration.new(v))
            else
              builder.send(:"with_#{k}", v)
            end
          end

          $things.add(builder.build)
        end
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
          modules = dir == "." ? [] : moduleize(dir)
          basename = File.basename(filename)
          method = basename[0...-7]
          modules << method
          ::OpenHAB::Transform.add_script(modules, script)
        end
      end

      private

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

      def restore_autoupdate_items
        return unless instance_variable_defined?(:@autoupdated_items)

        @autoupdated_items.each do |(item, meta)|
          item.meta["autoupdate"] = meta
        end
      end

      def populate_channel_types_from_api(api)
        api.channel_types.each do |ct_json|
          uid = org.openhab.core.thing.type.ChannelTypeUID.new(ct_json["UID"])
          builder = case ct_json["kind"]
                    when "STATE"
                      org.openhab.core.thing.type.ChannelTypeBuilder.state(uid, ct_json["label"], ct_json["itemType"])
                    when "TRIGGER"
                      org.openhab.core.thing.type.ChannelTypeBuilder.trigger(uid, ct_json["label"])
                    else
                      raise ArgumentError, "Unrecognized channel type kind #{ct_json["kind"]} for #{uid}"
                    end

          ct_json.each do |(k, v)|
            case k
            when "parameters", "parameterGroups", "label", "kind", "UID", "itemType"
              nil
            when "commandDescription"
              builder.with_command_description(build_command_description(v))
            when "stateDescription"
              builder.with_state_description_fragment(build_state_description_fragment(v))
            when "advanced"
              builder.is_advanced(v)
            else
              builder.send(:"with_#{k}", v)
            end
          end

          ct = builder.build
          Core::Mocks::ChannelTypeProvider.instance.add(ct)
        end
      end

      def build_command_description(json)
        org.openhab.core.types.CommandDescriptionBuilder.create
           .with_command_options(json["commandOptions"].map do |o|
                                   org.openhab.core.types.CommandOption.new(o["command"], o["label"])
                                 end)
           .build
      end

      def build_state_description_fragment(json)
        org.openhab.core.types.StateDescriptionFragmentBuilder.create
           .with_minimum(json["minimum"]&.to_d)
           .with_maximum(json["maximum"]&.to_d)
           .with_step(json["step"&.to_d])
           .with_pattern(json["pattern"])
           .with_read_only(json["readOnly"])
           .with_options(json["options"].map { |o| org.openhab.core.types.StateOption.new(o["value"], o["label"]) })
           .build
      end

      def populate_thing_types_from_api(api)
        api.thing_types.each do |tt_json|
          uid = org.openhab.core.thing.ThingTypeUID.new(tt_json["UID"])
          builder = org.openhab.core.thing.type.ThingTypeBuilder.instance(uid, tt_json["label"])
          tt_json.each do |(k, v)|
            case k
            when "UID", "label", "bridge"
              nil
            when "listed"
              builder.is_listed(v)
            when "channels"
              builder.with_channels(v.map { |c| build_channel_definition(c) })
            when "channelGroups"
              builder.with_channel_groups(v.map { |cg| build_channel_group_definition(cg) })
            else
              builder.send(:"with#{k[0].upcase}#{k[1..]}", v)
            end
          end

          tt = tt_json["bridge"] ? builder.build_bridge : builder.build
          Core::Mocks::ThingTypeProvider.instance.add(tt)
        end
      end

      def build_channel_definition(json)
        org.openhab.core.thing.type.ChannelDefinition.new(
          json["uid"],
          org.openhab.core.thing.type.ChannelTypeUID.new(json["typeUID"]),
          json["description"],
          json["properties"],
          nil
        )
      end

      def build_channel_group_definition(json)
        org.openhab.core.thing.type.ChannelGroupDefinition.new(
          json["uid"],
          org.openhab.core.thing.type.ChannelGroupTypeUID.new(json["typeUID"]),
          json["label"],
          json["description"]
        )
      end

      def build_channel(json)
        uid = org.openhab.core.thing.ChannelUID.new(json["uid"])
        builder = org.openhab.core.thing.binding.builder.ChannelBuilder.create(uid)

        json.each do |(k, v)|
          case k
          when "uid", "id", "linkedItems", "itemType"
            nil
          when "channelTypeUID"
            builder.with_type(org.openhab.core.thing.type.ChannelTypeUID.new((v)))
          when "configuration"
            builder.with_configuration(org.openhab.core.config.core.Configuration.new(v))
          when "kind"
            builder.with_kind(org.openhab.core.thing.type.ChannelKind.const_get(v, false))
          when "defaultTags"
            builder.with_default_tags(v.to_set)
          else
            builder.send("with_#{k}", v)
          end
        end

        builder.build
      end
    end

    RSpec.configure do |config|
      config.include Helpers
    end
  end
end
