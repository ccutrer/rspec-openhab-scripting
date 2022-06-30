# frozen_string_literal: true

module RSpec
  module OpenHAB
    module Items
      module_function

      # rubocop:disable Style/GlobalVars
      def populate_items_from_api(api)
        all_items = api.items
        all_items.each do |item_json|
          type, _dimension = item_json["type"].split(":")
          if type == "Group"
            if item_json["groupType"]
              type, _dimension = item_json["groupType"].split(":")
              klass = ::OpenHAB::DSL::Items.const_get(:"#{type}Item")
              base_item = klass.new(item_json["name"])
            end
            # TODO: create group function
            item = GroupItem.new(item_json["name"], base_item)
          else
            klass = ::OpenHAB::DSL::Items.const_get(:"#{type}Item")
            item = klass.new(item_json["name"])
          end

          item.label = item_json["label"]
          item_json["tags"].each do |tag|
            item.add_tag(tag)
          end
          item_json["metadata"]&.each do |key, config|
            item.meta[key] = config["value"], config["config"]
          end

          $ir.add(item)
        end
        all_items.each do |item_json| # rubocop:disable Style/CombinableLoops
          item_json["groupNames"].each do |group_name|
            next unless (group = $ir.get(group_name))

            group.add_member($ir.get(item_json["name"]))
          end
        end
      end
      # rubocop:enable Style/GlobalVars
    end
  end
end
