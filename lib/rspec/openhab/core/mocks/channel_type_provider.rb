# frozen_string_literal: true

module RSpec
  module OpenHAB
    module Core
      module Mocks
        class ChannelTypeProvider
          include org.openhab.core.thing.type.ChannelTypeProvider
          include Singleton

          def initialize
            @types = {}
          end

          def add(type)
            @types[type.uid] = type
          end

          def get_channel_types(_locale)
            @types.values
          end

          def get_channel_type(uid, _locale)
            @types[uid]
          end
        end
      end
    end
  end
end
