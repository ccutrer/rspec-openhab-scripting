# frozen_string_literal: true

module OpenHAB
  module Core
    class ItemProxy
      @proxies = {}

      class << self
        # ensure each item only has a single proxy, so that
        # expect(item).to receive(:method) works
        def new(item)
          @proxies.fetch(item.name) do
            @proxies[item.name] = super
          end
        end
      end
    end
  end
end
