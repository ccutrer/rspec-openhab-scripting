# frozen_string_literal: true

require "openhab/core/osgi"

module OpenHAB
  module DSL
    module Imports
      class ScriptExtensionManagerWrapper
        def initialize(manager)
          @manager = manager
        end

        def get(type)
          @manager.get("jruby", type)
        end
      end

      class EventAdmin
        include org.osgi.service.event.EventAdmin

        def initialize(event_manager)
          @event_manager = event_manager
        end

        def post_event(event)
          send_event(event)
        end

        def send_event(event)
          @event_manager.handle_event(event)
        end
      end

      # subclass to expose private fields
      class EventManager < org.openhab.core.internal.events.OSGiEventManager
        field_reader :typedEventFactories, :typedEventSubscribers
      end

      class << self
        def import_presets
          return if @imported

          @imported = true

          # some background java threads get created; kill them at_exit
          at_exit do
            threads_to_kill = %w[Finalizer NonBlockingInputStreamThread]
            Thread.list
                  .each { |t| t.kill if threads_to_kill.include?(t.name) }
          end

          # OSGiEventManager will create a ThreadedEventHandler on OSGi activation;
          # we're skipping that, and directly sending to a non-threaded event handler.
          em = EventManager.new
          eh = org.openhab.core.internal.events.EventHandler.new(em.typedEventSubscribers, em.typedEventFactories)
          at_exit { eh.close }
          ea = EventAdmin.new(eh)
          ep = org.openhab.core.internal.events.OSGiEventPublisher.new(ea)

          # the registries!
          mr = org.openhab.core.internal.items.MetadataRegistryImpl.new
          OpenHAB::Core::OSGI.register_service("org.openhab.core.items.MetadataRegistry", mr)
          ir = org.openhab.core.internal.items.ItemRegistryImpl.new(mr)
          ss = org.openhab.core.test.storage.VolatileStorageService.new
          ir.managed_provider = mip = org.openhab.core.items.ManagedItemProvider.new(ss, nil)
          ir.add_provider(mip)
          mip.add_provider_change_listener(ir)
          tr = org.openhab.core.thing.internal.ThingRegistryImpl.new
          rr = org.openhab.core.automation.internal.RuleRegistryImpl.new
          iclr = org.openhab.core.thing.link.ItemChannelLinkRegistry.new(tr, ir)

          # set up stuff accessed from rules
          preset = org.openhab.core.automation.module.script.internal.defaultscope
                      .DefaultScriptScopeProvider.new(ir, tr, rr, ep)
          preset.default_presets.each do |preset_name|
            preset.import_preset(nil, preset_name).each do |(name, value)|
              next if name == "File"

              if value.respond_to?(:ruby_class)
                Object.const_set(name, value.ruby_class)
              elsif /[[:upper:]]/.match?(name[0])
                Object.const_set(name, value)
              else
                eval("$#{name} = value", binding, __FILE__, __LINE__) # $ir = value # rubocop:disable Security/Eval
              end
            end
          end

          rp = org.openhab.core.automation.module.script.rulesupport.shared.ScriptedRuleProvider.new
          cmhf = org.openhab.core.automation.module.script.rulesupport.internal.ScriptedCustomModuleHandlerFactory.new
          cmtp = org.openhab.core.automation.module.script.rulesupport.internal.ScriptedCustomModuleTypeProvider.new
          pmhf = org.openhab.core.automation.module.script.rulesupport.internal.ScriptedPrivateModuleHandlerFactory.new
          se = org.openhab.core.automation.module.script.rulesupport.internal
                  .RuleSupportScriptExtension.new(rr, rp, cmhf, cmtp, pmhf)
          sew = ScriptExtensionManagerWrapper.new(se)
          $se = $scriptExtension = sew # rubocop:disable Style/GlobalVars

          # need to created some singletons referencing registries
          org.openhab.core.model.script.ScriptServiceUtil.new(ir, tr, ep, nil, nil)
          org.openhab.core.model.script.internal.engine.action.SemanticsActionService.new(ir)

          # link up event bus infrastructure
          iu = org.openhab.core.internal.items.ItemUpdater.new(ir)
          ief = org.openhab.core.items.events.ItemEventFactory.new

          sc = org.openhab.core.internal.common.SafeCallerImpl.new({})
          aum = org.openhab.core.thing.internal.AutoUpdateManager.new({ "enabled" => "true" }, nil, ep, iclr, mr, tr)
          cm = org.openhab.core.thing.internal.CommunicationManager.new(aum, nil, nil, iclr, ir, nil, ep, sc, tr)

          em.add_event_subscriber(iu)
          em.add_event_subscriber(cm)
          em.add_event_factory(ief)
        end
      end
    end
  end
end

OpenHAB::DSL.singleton_class.prepend(OpenHAB::DSL::Imports)
