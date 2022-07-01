# frozen_string_literal: true

# rubocop:disable Style/GlobalVars
module RSpec
  module OpenHAB
    module Items
      class << self
        def populate_items_from_api(api)
          all_items = api.items

          gfh = org.openhab.core.internal.items.GroupFunctionHelper.new

          all_items.each do |item_json|
            type, _dimension = item_json["type"].split(":")
            if type == "Group"
              if item_json["groupType"]
                type, _dimension = item_json["groupType"].split(":")
                klass = ::OpenHAB::DSL::Items.const_get(:"#{type}Item")
                base_item = klass.new(item_json["name"])
              end
              if item_json["function"]
                dto = org.openhab.core.items.dto.GroupFunctionDTO.new
                dto.name = item_json.dig("function", "name")
                dto.params = item_json.dig("function", "params")
                function = gfh.create_group_function(dto, base_item)
              end
              item = GroupItem.new(item_json["name"], base_item, function)
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
      end

      def autoupdate_all_items
        @autoupdated_items ||= {}
        $ir.for_each do |_provider, item|
          @autoupdated_items[item] = item.meta.delete("autoupdate") if item.meta.key?("autoupdate")
        end
      end

      private

      def restore_autoupdate_items
        return unless instance_variable_defined?(:@autoupdated_items)

        @autoupdated_items.each do |(item, meta)|
          item.meta["autoupdate"] = meta
        end
      end

      ::RSpec.configure do |config|
        config.include(self)
        config.after do
          restore_autoupdate_items
        end
      end
    end
  end
end
# rubocop:enable Style/GlobalVars
