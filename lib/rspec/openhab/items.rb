# frozen_string_literal: true

module RSpec
  module OpenHAB
    module Items
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
          end
          all_items.each do |item_json| # rubocop:disable Style/CombinableLoops
            item_json["groupNames"].each do |group_name|
              next unless (group = $ir.get(group_name))

              group.add_member($ir.get(item_json["name"]))
            end
          end
        end
      end
    end
  end
end
