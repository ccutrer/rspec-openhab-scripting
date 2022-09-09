# frozen_string_literal: true

module RSpec
  module OpenHAB
    Object.include RSpec::OpenHAB::Helpers if defined?(IRB)

    if RSpec.respond_to?(:configure)
      RSpec.configure do |config|
        config.add_setting :include_openhab_bindings, default: true
        config.add_setting :include_openhab_jsondb, default: true
        config.add_setting :private_openhab_confdir, default: false
        config.add_setting :use_root_openhab_instance, default: false

        config.before(:suite) do
          Helpers.launch_karaf(include_bindings: config.include_openhab_bindings,
                               include_jsondb: config.include_openhab_jsondb,
                               private_confdir: config.private_openhab_confdir,
                               use_root_instance: config.use_root_openhab_instance)
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
          @known_rules = ::OpenHAB::Core.rule_registry.all.map(&:uid)
        end

        config.before do
          @item_provider = ::OpenHAB::DSL::Items::ItemProvider.send(:new)
          allow(::OpenHAB::DSL::Items::ItemProvider).to receive(:instance).and_return(@item_provider)
        end

        config.after do
          # remove rules created during the spec
          (::OpenHAB::Core.rule_registry.all.map(&:uid) - @known_rules).each do |uid|
            ::OpenHAB::Core.rule_registry.remove(uid)
          end
          $ir.remove_provider(@item_provider) if @item_provider
          ::OpenHAB::DSL::Timers.timer_manager.cancel_all
          Timecop.return
          restore_autoupdate_items
          Core::Mocks::PersistenceService.instance.reset
        end
      end
    end
  end
end
