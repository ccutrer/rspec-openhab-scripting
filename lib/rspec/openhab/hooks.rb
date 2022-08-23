# frozen_string_literal: true

module RSpec
  module OpenHAB
    RSpec.configure do |config|
      config.before(:suite) do
        Helpers.populate_things_from_api if ::OpenHAB::DSL::Imports.api.authenticated?
        Helpers.populate_items_from_api
        Helpers.load_transforms
        Helpers.suspend_rules do
          Helpers.auto_requires
          Helpers.load_rules
        end
      end

      config.before do
        suspend_rules do
          $ir.for_each do |_provider, item|
            next if item.is_a?(GroupItem) # groups only have calculated states

            item.state = NULL unless item.raw_state == NULL
          end
        end
      end

      config.after do
        ::OpenHAB::DSL::Timers.timer_manager.cancel_all
        Timecop.return
        restore_autoupdate_items
        Core::Mocks::PersistenceService.instance.reset
      end
    end
  end
end
