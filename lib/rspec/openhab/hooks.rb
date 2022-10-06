# frozen_string_literal: true

module RSpec
  module OpenHAB
    Object.include RSpec::OpenHAB::Helpers if defined?(IRB)

    Helpers.launch_karaf(
      include_bindings: Configuration.include_bindings,
      include_jsondb: Configuration.include_jsondb,
      private_confdir: Configuration.private_confdir,
      use_root_instance: Configuration.use_root_instance
    )

    if RSpec.respond_to?(:configure)
      RSpec.configure do |config|
        config.before(:suite) do
          config.include ::OpenHAB::Core::EntityLookup
          Helpers.autorequires unless Configuration.private_confdir
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
          if defined?(::OpenHAB::DSL::Items::ItemProvider)
            @item_provider = ::OpenHAB::DSL::Items::ItemProvider.send(:new)
            allow(::OpenHAB::DSL::Items::ItemProvider).to receive(:instance).and_return(@item_provider)
          end
          if defined?(::OpenHAB::DSL::Things::ThingProvider)
            @thing_provider = ::OpenHAB::DSL::Things::ThingProvider.send(:new)
            allow(::OpenHAB::DSL::Things::ThingProvider).to receive(:instance).and_return(@thing_provider)
          end
        end

        config.after do
          # remove rules created during the spec
          (::OpenHAB::Core.rule_registry.all.map(&:uid) - @known_rules).each do |uid|
            remove_rule(uid) if defined?(remove_rule)
          end
          $ir.remove_provider(@item_provider) if instance_variable_defined?(:@item_provider) && @item_provider
          ::OpenHAB::Core::ItemProxy.reset_cache
          $things.remove_provider(@thing_provider) if instance_variable_defined?(:@thing_provider) && @thing_provider
          ::OpenHAB::DSL::Things::Thing.reset_cache
          ::OpenHAB::DSL::Timers.timer_manager.cancel_all
          Timecop.return
          restore_autoupdate_items
          Core::Mocks::PersistenceService.instance.reset
        end
      end
    end
  end
end
