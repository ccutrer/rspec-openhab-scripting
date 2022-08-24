# frozen_string_literal: true

require "singleton"

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
          @pending_events = nil
        end

        def post_event(event)
          send_event(event)
        end

        def send_event(event)
          if @pending_events
            @pending_events << event
            return
          end

          @pending_events = []
          @event_manager.handle_event(event)

          @event_manager.handle_event(@pending_events.shift) until @pending_events.empty?

          @pending_events = nil
        end
      end

      class BundleContext
        include org.osgi.framework.BundleContext

        attr_reader :bundles

        def initialize(event_manager)
          @event_manager = event_manager
          @bundles = []
        end

        def register_service(klass, service, _properties)
          klass = klass.to_s
          unless klass == "org.openhab.core.events.EventSubscriber"
            raise NotImplementedError "Don't know how to process service #{service.inspect} of type #{klass.name}"
          end

          @event_manager.add_event_subscriber(service)
        end

        def get_service_reference(klass); end
        def get_service(klass); end
        def add_bundle_listener(listener); end
      end

      class BundleResolver
        include org.openhab.core.util.BundleResolver

        def initialize
          @bundles = {}
        end

        def register(klass, bundle)
          @bundles[klass] = bundle
        end

        def resolve_bundle(klass)
          @bundles[klass]
        end
      end

      # don't depend on org.openhab.core.test
      class VolatileStorageService
        include org.openhab.core.storage.StorageService

        def initialize
          @storages = {}
        end

        def get_storage(name, *)
          @storages[name] ||= VolatileStorage.new
        end
      end

      class VolatileStorage < Hash
        include org.openhab.core.storage.Storage

        alias_method :get, :[]
        alias_method :put, :[]=
        alias_method :remove, :delete
        alias_method :contains_key, :key?

        alias_method :get_keys, :keys
        alias_method :get_values, :values
      end

      class Bundle
        include org.osgi.framework.Bundle
        INSTALLED = 2

        def initialize(*jar_args)
          return if jar_args.empty?

          file = Jars.find_jar(*jar_args)
          @jar = java.util.jar.JarFile.new(file)
          @symbolic_name = jar_args[1]
          @version = org.osgi.framework.Version.new(jar_args[2].tr("-", "."))
        end

        attr_accessor :symbolic_name, :version

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

      class ComponentContext
        include org.osgi.service.component.ComponentContext

        attr_reader :properties, :bundle_context

        def initialize(bundle_context)
          @properties = java.util.Hashtable.new
          @bundle_context = bundle_context
        end
      end

      # subclass to expose private fields
      class EventManager < org.openhab.core.internal.events.OSGiEventManager
        field_reader :typedEventFactories, :typedEventSubscribers
      end

      # reimplement to not use a thread
      class EventHandler
        def initialize(typed_event_subscribers, typed_event_factories)
          @typed_event_subscribers = typed_event_subscribers
          @typed_event_factories = typed_event_factories
        end

        def handle_event(osgi_event)
          type = osgi_event.get_property("type")
          payload = osgi_event.get_property("payload")
          topic = osgi_event.get_property("topic")
          source = osgi_event.get_property("source")

          if type.is_a?(String) && payload.is_a?(String) && topic.is_a?(String)
            handle_event_internal(type, payload, topic, source) unless type.empty? || payload.empty? || topic.empty?
          else
            logger.error("The handled OSGi event is invalid. " \
                         "Expect properties as string named 'type', 'payload', and 'topic'. " \
                         "Received event properties are: #{properties.keys.inspect}")
          end
        end

        private

        def handle_event_internal(type, payload, topic, source)
          event_factory = @typed_event_factories[type]
          unless event_factory
            logger.debug("Could not find an Event Factory for the event type '#{type}'.")
            return
          end

          event_subscribers = event_subscribers(type)
          return if event_subscribers.empty?

          event = create_event(event_factory, type, payload, topic, source)
          return unless event

          dispatch_event(event_subscribers, event)
        end

        def event_subscribers(event_type)
          event_type_subscribers = @typed_event_subscribers[event_type]
          all_event_type_subscribers = @typed_event_subscribers["ALL"]

          subscribers = java.util.HashSet.new
          subscribers.add_all(event_type_subscribers) if event_type_subscribers
          subscribers.add_all(all_event_type_subscribers) if all_event_type_subscribers
          subscribers
        end

        def create_event(event_factory, type, payload, topic, source)
          event_factory.create_event(type, topic, payload, source)
        rescue Exception => e
          logger.warn("Creation of event failed, because one of the " \
                      "registered event factories has thrown an exception: #{e.inspect}")
          nil
        end

        def dispatch_event(event_subscribers, event)
          event_subscribers.each do |event_subscriber|
            filter = event_subscriber.event_filter
            if filter.nil? || filter.apply(event)
              begin
                event_subscriber.receive(event)
              rescue Exception => e
                logger.warn(
                  "Dispatching/filtering event for subscriber '#{event_subscriber.class}' failed: #{e.inspect}"
                )
              end
            else
              logger.trace("Skip event subscriber (#{event_subscriber.class}) because of its filter.")
            end
          end
        end
      end

      org.openhab.core.automation.internal.TriggerHandlerCallbackImpl.field_accessor :executor
      org.openhab.core.automation.internal.TriggerHandlerCallbackImpl.field_reader :ruleUID
      class SynchronousExecutor
        include java.util.concurrent.ScheduledExecutorService
        include Singleton

        def submit(runnable)
          runnable.respond_to?(:run) ? runnable.run : runnable.call

          java.util.concurrent.CompletableFuture.completed_future(nil)
        end

        def execute(runnable)
          runnable.run
        end

        def shutdown_now; end

        def shutdown?
          false
        end
      end

      class SafeCaller
        include org.openhab.core.common.SafeCaller
        include org.openhab.core.common.SafeCallerBuilder

        def create(target, _interface_type)
          @target = target
          self
        end

        def build
          @target
        end

        def with_timeout(_timeout)
          self
        end

        def with_identifier(_identifier)
          self
        end

        def on_exception(_handler)
          self
        end

        def on_timeout(_handler)
          self
        end

        def with_async
          self
        end
      end

      class CallbacksMap < java.util.HashMap
        def put(_rule_uid, trigger_handler)
          trigger_handler.executor.shutdown_now
          trigger_handler.executor = SynchronousExecutor.instance
          super
        end
      end

      class SynchronousExecutorMap
        include java.util.Map

        def get(_key)
          SynchronousExecutor.instance
        end
      end

      @imported = false

      class << self
        attr_accessor :api

        def import_presets
          return if @imported

          @imported = true

          org.openhab.core.common.ThreadPoolManager.field_accessor :pools
          org.openhab.core.common.ThreadPoolManager.pools = SynchronousExecutorMap.new

          # OSGiEventManager will create a ThreadedEventHandler on OSGi activation;
          # we're skipping that, and directly sending to a non-threaded event handler.
          em = EventManager.new
          eh = EventHandler.new(em.typedEventSubscribers, em.typedEventFactories)
          ea = EventAdmin.new(eh)
          ep = org.openhab.core.internal.events.OSGiEventPublisher.new(ea)
          bc = BundleContext.new(em)
          cc = ComponentContext.new(bc)
          cc.properties["measurementSystem"] = api.measurement_system if api
          resolver = BundleResolver.new

          # the registries!
          ss = VolatileStorageService.new
          mr = org.openhab.core.internal.items.MetadataRegistryImpl.new
          OpenHAB::Core::OSGI.register_service(mr)
          mr.managed_provider = mmp = org.openhab.core.internal.items.ManagedMetadataProviderImpl.new(ss)
          mr.add_provider(mmp)
          gmp = org.openhab.core.model.item.internal.GenericMetadataProvider.new
          mr.add_provider(gmp)
          ir = org.openhab.core.internal.items.ItemRegistryImpl.new(mr)
          ir.managed_provider = mip = org.openhab.core.items.ManagedItemProvider.new(ss, nil)
          ir.add_provider(mip)
          ir.event_publisher = ep
          up = org.openhab.core.internal.i18n.I18nProviderImpl.new(cc)
          ir.unit_provider = up
          ir.item_state_converter = isc = org.openhab.core.internal.items.ItemStateConverterImpl.new(up)
          tr = org.openhab.core.thing.internal.ThingRegistryImpl.new
          tr.managed_provider = mtp = org.openhab.core.thing.ManagedThingProvider.new(ss)
          tr.add_provider(mtp)
          mtr = org.openhab.core.automation.internal.type.ModuleTypeRegistryImpl.new
          rr = org.openhab.core.automation.internal.RuleRegistryImpl.new
          rr.module_type_registry = mtr
          rr.managed_provider = mrp = org.openhab.core.automation.ManagedRuleProvider.new(ss)
          rr.add_provider(mrp)
          iclr = org.openhab.core.thing.link.ItemChannelLinkRegistry.new(tr, ir)
          iclr.add_provider(RSpec::OpenHAB::Core::Mocks::ItemChannelLinkProvider.instance)
          OpenHAB::Core::OSGI.register_service(iclr)
          ctr = org.openhab.core.thing.type.ChannelTypeRegistry.new
          OpenHAB::Core::OSGI.register_service(ctr)
          ctr.add_channel_type_provider(RSpec::OpenHAB::Core::Mocks::ChannelTypeProvider.instance)
          ttr = org.openhab.core.thing.type.ThingTypeRegistry.new(ctr)
          OpenHAB::Core::OSGI.register_service(ttr)
          ttr.add_thing_type_provider(RSpec::OpenHAB::Core::Mocks::ThingTypeProvider.instance)
          cgtr = org.openhab.core.thing.type.ChannelGroupTypeRegistry.new

          safe_emf = org.openhab.core.model.core.internal.SafeEMFImpl.new
          model_repository = org.openhab.core.model.core.internal.ModelRepositoryImpl.new(safe_emf)

          # set up state descriptions
          sds = org.openhab.core.internal.service.StateDescriptionServiceImpl.new
          gip = org.openhab.core.model.item.internal.GenericItemProvider.new(model_repository, gmp, {})
          sds.add_state_description_fragment_provider(gip)
          msdfp = org.openhab.core.internal.items.MetadataStateDescriptionFragmentProvider.new(mr, {})
          sds.add_state_description_fragment_provider(msdfp)
          csdp = org.openhab.core.thing.internal.ChannelStateDescriptionProvider.new(iclr, ttr, tr)
          csdp.activate(org.osgi.framework.Constants::SERVICE_RANKING => java.lang.Integer.new(-1))
          sds.add_state_description_fragment_provider(csdp)
          ir.state_description_service = sds

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
          $se = $scriptExtension = sew

          # need to create some singletons referencing registries
          org.openhab.core.model.script.ScriptServiceUtil.new(ir, tr, ep, nil, nil)
          org.openhab.core.model.script.internal.engine.action.SemanticsActionService.new(ir)

          # link up event bus infrastructure
          iu = org.openhab.core.internal.items.ItemUpdater.new(ir)

          sc = SafeCaller.new
          aum = org.openhab.core.thing.internal.AutoUpdateManager.new(
            { "enabled" => true, "sendOptimisticUpdates" => true }, ctr, ep, iclr, mr, tr
          )
          spf = org.openhab.core.thing.internal.profiles.SystemProfileFactory.new(ctr, nil, resolver)
          cm = org.openhab.core.thing.internal.CommunicationManager.new(aum, ctr, spf, iclr, ir, isc, ep, sc, tr)

          em.add_event_subscriber(iu)
          em.add_event_subscriber(cm)
          em.add_event_factory(org.openhab.core.items.events.ItemEventFactory.new)
          em.add_event_factory(org.openhab.core.thing.events.ThingEventFactory.new)

          # set up the rules engine part 2
          k = org.openhab.core.automation.internal.module.factory.CoreModuleHandlerFactory
          # depending on OH version, this class is set up differently
          cmhf = begin
            cmhf = k.new
            cmhf.item_registry = ir
            cmhf.event_publisher = ep
            cmhf.activate(bc)
            cmhf
          rescue ArgumentError
            k.new(bc, ep, ir)
          end

          rs = org.openhab.core.internal.service.ReadyServiceImpl.new
          re = org.openhab.core.automation.internal.RuleEngineImpl.new(mtr, rr, ss, rs)
          OpenHAB::Core::OSGI.register_service(re)

          # overwrite thCallbacks to one that will spy to remove threading
          field = re.class.java_class.declared_field("thCallbacks")
          field.accessible = true
          field.set(re, CallbacksMap.new)
          re.class.field_accessor :executor
          re.executor = SynchronousExecutor.instance
          re.add_module_handler_factory(cmhf)
          re.add_module_handler_factory(scmhf)
          re.add_module_handler_factory(spmhf)
          re.on_ready_marker_added(nil)

          # enable event logging
          el = org.openhab.core.io.monitor.internal.EventLogger.new(rs)
          em.add_event_subscriber(el)
          el.on_ready_marker_added(nil)

          # set up persistence
          psr = org.openhab.core.persistence.internal.PersistenceServiceRegistryImpl.new
          org.openhab.core.persistence.extensions.PersistenceExtensions.new(psr)
          psr.activate("default" => "default")
          ps = RSpec::OpenHAB::Core::Mocks::PersistenceService.instance
          psr.add_persistence_service(ps)

          pm = org.openhab.core.persistence.internal.PersistenceManagerImpl.new(nil, ir, sc, rs)
          pm.add_persistence_service(ps)
          pm.on_ready_marker_added(nil)

          # set up ThingManager so we can trigger channels
          localizer = org.openhab.core.thing.i18n.ThingStatusInfoI18nLocalizationService.new
          tm = org.openhab.core.thing.internal.ThingManagerImpl.new(
            resolver,
            cgtr,
            ctr,
            cm,
            nil,
            nil,
            ep,
            iclr,
            rs,
            sc,
            ss,
            tr,
            localizer,
            ttr
          )
          thf = RSpec::OpenHAB::Core::Mocks::ThingHandlerFactory.new
          this_bundle = Bundle.new
          this_bundle.symbolic_name = "org.openhab.automation.jrubyscripting.rspec"
          resolver.register(thf.class.java_class, this_bundle)
          tm.add_thing_handler_factory(thf)
          tm.on_ready_marker_added(org.openhab.core.service.ReadyMarker.new(nil, this_bundle.symbolic_name))
        end
      end
    end
  end
end

# OpenHAB::DSL.singleton_class.prepend(OpenHAB::DSL::Imports)
