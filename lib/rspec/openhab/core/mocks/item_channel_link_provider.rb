# frozen_string_literal: true

module RSpec
  module OpenHAB
    module Core
      module Mocks
        class ItemChannelLinkProvider
          include org.openhab.core.thing.link.ItemChannelLinkProvider
          include Singleton

          def initialize
            @listeners = []
            @links = []
          end

          def add_provider_change_listener(listener)
            @listeners << listener
          end

          def remove_provider_change_listener(listener)
            @listeners.delete(listener)
          end

          def all
            @links
          end

          def add(link)
            @links << link
            @listeners.each { |l| l.added(self, link) }
          end
        end
      end
    end
  end
end
