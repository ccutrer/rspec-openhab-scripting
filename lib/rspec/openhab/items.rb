# frozen_string_literal: true

module RSpec
  module OpenHAB
    module Items
      class ThingHandler
        include org.openhab.core.thing.binding.ThingHandler

        attr_reader :thing

        def initialize(thing)
          @thing = thing
        end

        def handle_command(channel, command); end
      end

      class << self
        def populate_items_from_api(api)
          all_items = api.items

          gfh = org.openhab.core.internal.items.GroupFunctionHelper.new
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
                function = gfh.create_group_function(dto, base_item)
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

        def populate_things_from_api(api)
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

            thing = builder.build
            # pretend everything is online so that AutoUpdateManager won't reject updates
            # to items linked to offline channels
            thing.status_info = org.openhab.core.thing.binding.builder.ThingStatusInfoBuilder
                                   .create(org.openhab.core.thing.ThingStatus::ONLINE).build
            handler = ThingHandler.new(thing)
            thing.handler = handler
            $things.add(thing)
          end
        end

        private

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
    end
  end
end
