# frozen_string_literal: true

module RSpec
  module OpenHAB
    if defined?(IRB)
      Object.include RSpec::OpenHAB::Helpers
      launch_karaf
      autorequires
      set_up_autoupdates
      load_rules
    end

    if RSpec.respond_to?(:configure)
      RSpec.configure do |config|
        config.add_setting :include_openhab_bindings, default: true
        config.add_setting :include_openhab_jsondb, default: true
        config.add_setting :private_openhab_confdir, default: false

        config.before(:suite) do
          Helpers.launch_karaf(include_bindings: config.include_openhab_bindings,
                               include_jsondb: config.include_openhab_jsondb,
                               private_confdir: config.private_openhab_confdir)
          config.include ::OpenHAB::Core::EntityLookup
          Helpers.autorequires unless config.private_openhab_confdir
          Helpers.send(:set_up_autoupdates)
          Helpers.load_transforms
          Helpers.load_rules
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
end
