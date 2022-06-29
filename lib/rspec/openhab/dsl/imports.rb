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

      class BundleContext
        include org.osgi.framework.BundleContext

        def initialize(event_manager)
          @event_manager = event_manager
        end

        def register_service(klass, service, _properties)
          klass = klass.to_s
          unless klass == "org.openhab.core.events.EventSubscriber"
            raise NotImplementedError "Don't know how to process service #{service.inspect} of type #{klass.name}"
          end

          @event_manager.add_event_subscriber(service)
        end
      end

      class Bundle
        include org.osgi.framework.Bundle
        INSTALLED = 2

        def initialize(*jar_args)
          jar = Jars.send(:to_jar, *jar_args)
          file = File.join(Jars.home, jar)
          @jar = java.util.jar.JarFile.new(file.to_s)
          @symbolic_name = jar_args[1]
          @version = org.osgi.framework.Version.new(jar_args[2].tr("-", "."))
        end

        attr_reader :symbolic_name, :version

        def state
          INSTALLED
        end

        def find_entries(path, pattern, recurse)
          pattern ||= recurse ? "**" : "*"
          full_pattern = File.join(path, pattern)
          entries = @jar.entries.select do |e|
            File.fnmatch(full_pattern, e.name)
          end
          java.util.Collections.enumeration(entries.map { |e| java.net.URL.new("jar:file://#{@jar.name}!/#{e.name}") })
        end
      end

      # subclass to expose private fields
      class EventManager < org.openhab.core.internal.events.OSGiEventManager
        field_reader :typedEventFactories, :typedEventSubscribers
      end

      @imported = false

      class << self
        def import_presets
          return if @imported

          @imported = true

          # some background java threads get created; kill them at_exit
          at_exit do
            status = 0
            status = $!.status if $!.is_a?(SystemExit)
            exit!(status)
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
          tr = org.openhab.core.thing.internal.ThingRegistryImpl.new
          mtr = org.openhab.core.automation.internal.type.ModuleTypeRegistryImpl.new
          rr = org.openhab.core.automation.internal.RuleRegistryImpl.new
          rr.module_type_registry = mtr
          rr.managed_provider = mrp = org.openhab.core.automation.ManagedRuleProvider.new(ss)
          rr.add_provider(mrp)
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

          # set up the rules engine part 1
          mtrbp = org.openhab.core.automation.internal.provider.ModuleTypeResourceBundleProvider.new(nil)
          mtgp = org.openhab.core.automation.internal.parser.gson.ModuleTypeGSONParser.new
          mtrbp.add_parser(mtgp, {})
          bundle = Bundle.new("org.openhab.core.bundles",
                              "org.openhab.core.automation.module.script.rulesupport",
                              OpenHAB::Core.openhab_version)
          mtrbp.process_automation_provider(bundle)
          bundle = Bundle.new("org.openhab.core.bundles",
                              "org.openhab.core.automation",
                              OpenHAB::Core.openhab_version)
          mtrbp.process_automation_provider(bundle)
          mtr.add_provider(mtrbp)

          # set up script support stuff
          srp = org.openhab.core.automation.module.script.rulesupport.shared.ScriptedRuleProvider.new
          rr.add_provider(srp)
          scmhf = org.openhab.core.automation.module.script.rulesupport.internal.ScriptedCustomModuleHandlerFactory.new
          scmtp = org.openhab.core.automation.module.script.rulesupport.internal.ScriptedCustomModuleTypeProvider.new
          mtr.add_provider(scmtp)
          spmhf = org.openhab.core.automation.module.script.rulesupport.internal.ScriptedPrivateModuleHandlerFactory.new
          se = org.openhab.core.automation.module.script.rulesupport.internal
                  .RuleSupportScriptExtension.new(rr, srp, scmhf, scmtp, spmhf)
          sew = ScriptExtensionManagerWrapper.new(se)
          $se = $scriptExtension = sew # rubocop:disable Style/GlobalVars

          # need to create some singletons referencing registries
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

          # set up the rules engine part 2
          bc = BundleContext.new(em)
          cmhf = org.openhab.core.automation.internal.module.factory.CoreModuleHandlerFactory.new(bc, ep, ir)

          rs = org.openhab.core.internal.service.ReadyServiceImpl.new
          re = org.openhab.core.automation.internal.RuleEngineImpl.new(mtr, rr, ss, rs)
          re.add_module_handler_factory(cmhf)
          re.add_module_handler_factory(scmhf)
          re.add_module_handler_factory(spmhf)
          re.onReadyMarkerAdded(nil)
        end
      end
    end
  end
end

OpenHAB::DSL.singleton_class.prepend(OpenHAB::DSL::Imports)
