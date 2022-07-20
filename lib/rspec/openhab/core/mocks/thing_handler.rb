# frozen_string_literal: true

# rubocop:disable Naming have to follow java interface names
module RSpec
  module OpenHAB
    module Core
      module Mocks
        class ThingHandler
          include org.openhab.core.thing.binding.BridgeHandler

          attr_reader :thing, :callback

          def initialize(thing = nil)
            # have to handle the interface method
            if thing.nil?
              status_info = org.openhab.core.thing.binding.builder.ThingStatusInfoBuilder
                               .create(org.openhab.core.thing.ThingStatus::ONLINE).build
              @callback.status_updated(self.thing, status_info)
              return
            end

            # ruby initializer here
            @thing = thing
          end

          def handle_command(channel, command); end

          def set_callback(callback)
            @callback = callback
          end

          def child_handler_initialized(child_handler, child_thing); end
        end

        class ThingHandlerFactory < org.openhab.core.thing.binding.BaseThingHandlerFactory
          def supportsThingType(_type)
            true
          end

          def createHandler(thing)
            ThingHandler.new(thing)
          end
        end
      end
    end
  end
end
# rubocop:enable Naming
