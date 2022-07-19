# frozen_string_literal: true

module RSpec
  module OpenHAB
    module Core
      module Mocks
        class ThingTypeProvider
          include org.openhab.core.thing.binding.ThingTypeProvider
          include Singleton

          def initialize
            @types = {}
          end

          def add(type)
            @types[type.uid] = type
          end

          def get_thing_types(_locale)
            @types.values
          end

          def get_thing_type(uid, _locale)
            @types[uid]
          end
        end
      end
    end
  end
end
