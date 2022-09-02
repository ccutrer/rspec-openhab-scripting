# frozen_string_literal: true

require "fileutils"
require "jruby"
require "shellwords"
require "time"

require_relative "jruby"
require_relative "shell"

module RSpec
  module OpenHAB
    class Karaf
      class ScriptExtensionManagerWrapper
        def initialize(manager)
          @manager = manager
        end

        def get(type)
          @manager.get(type, "jruby")
        end
      end
      private_constant :ScriptExtensionManagerWrapper

      attr_reader :path

      def initialize(path)
        @path = path
      end

      def launch
        load_boot_jars
        set_env
        set_java_properties
        set_java_properties_from_env
        redirect_instances
        create_instance
        start_instance
      end

      private

      # create a private instances configuration
      def redirect_instances
        # this is normally done directly in bin/karaf with a -D JAVA_OPT
        orig_instances = "#{java.lang.System.get_property("karaf.data")}/tmp/instances"

        instances_path = "#{path}/instances"
        java.lang.System.set_property("karaf.instances", instances_path)
        FileUtils.mkdir_p(instances_path)

        new_instance_properties = "#{instances_path}/instance.properties"
        return if File.exist?(new_instance_properties) && File.stat(new_instance_properties).size != 0

        FileUtils.cp("#{orig_instances}/instance.properties", new_instance_properties)
      end

      def create_instance
        find_karaf_instance_jar
        # OSGI isn't up yet, so have to create the service directly
        service = org.apache.karaf.instance.core.internal.InstanceServiceImpl.new
        settings = org.apache.karaf.instance.core.InstanceSettings.new(0, 0, 0, path, nil, nil, nil)
        root_instance = service.instances.find(&:root?)
        raise ArgumentError "No root instance found to clone... has OpenHAB run yet?" unless root_instance

        return if service.get_instance("rspec")

        service.clone_instance(root_instance.name, "rspec", settings, false)
        cleanup_clone
        prune_startlevels
        minimize_installed_features
      ensure
        extra_loaders = ::JRuby.runtime.instance_config.extra_loaders
        loader = extra_loaders.find { |l| l.class_loader == @karaf_instance_loader }
        extra_loaders.remove(loader)
      end

      def start_instance
        # these are all from karaf.instances's startup code with
        # the exception of not having data be a subdir
        java.lang.System.set_property("karaf.base", path)
        java.lang.System.set_property("karaf.data", path)
        java.lang.System.set_property("karaf.etc", "#{path}/etc")
        java.lang.System.set_property("karaf.log", "#{path}/log")
        java.lang.System.set_property("java.io.tmpdir", "#{path}/tmp")
        java.lang.System.set_property("karaf.startLocalConsole", "false")
        java.lang.System.set_property("karaf.startRemoteShell", "false")
        # set in bin/setenv to OPENHAB_USERDATA; need to move it
        java.lang.System.set_property("felix.cm.dir", "#{path}/config")
        # not handled by karaf instances
        java.lang.System.set_property("openhab.userdata", path)
        java.lang.System.set_property("openhab.logdir", "#{path}/log")
        # we don't need a shutdown socket
        java.lang.System.set_property("karaf.shutdown.port", "-1")
        # ensure we're not logging to stdout
        java.util.logging.LogManager.log_manager.reset

        # see https://github.com/jruby/jruby/issues/7338
        @mutex = Mutex.new
        # launch it! (don't use Main.main; it will wait for it to be
        # shut down externally)
        @all_bundles_continue = nil
        @main = org.apache.karaf.main.Main.new([])
        launch_karaf
        at_exit do
          @main.destroy
          # OSGi/OpenHAB leave a ton of threads around. Kill ourselves ASAP
          code = if $!.nil? || ($!.is_a?(SystemExit) && $!.success?)
                   0
                 elsif $!.is_a?(SystemExit)
                   $!.status
                 else
                   puts $!.inspect
                   1
                 end
          exit!(code)
        end

        set_up_bundle_listener
        wait_for_start
        set_jruby_script_presets
        @main
      end

      def launch_karaf
        # we need to access internals, since we're reproducing much of Main.launch
        klass = org.apache.karaf.main.Main
        klass.field_accessor :classLoader, :activatorManager
        klass.field_writer :framework
        klass.field_reader :LOG
        org.apache.karaf.main.ConfigProperties.field_reader :props, :defaultBundleStartlevel, :karafEtc,
                                                            :defaultStartLevel
        klass.class_eval do
          def send_private(method_name, *args)
            method_name = method_name.to_s
            method = self.class.java_class.declared_methods.find { |m| m.name == method_name }
            method.accessible = true
            method.invoke(self, *args)
          end

          def launch_simple
            self.config = org.apache.karaf.main.ConfigProperties.new
            config.perform_init
            log4j_config_path = "#{java.lang.System.get_property("karaf.etc")}/org.ops4j.pax.logging.cfg"
            org.apache.karaf.main.util.BootstrapLogManager.set_properties(config.props, log4j_config_path)
            org.apache.karaf.main.util.BootstrapLogManager.configure_logger(self.class.LOG)

            bundle_dirs = send_private(:getBundleRepos)
            resolver = org.apache.karaf.main.util.SimpleMavenResolver.new(bundle_dirs)
            self.classLoader = send_private(:createClassLoader, resolver)
            factory = send_private(:loadFrameworkFactory, classLoader)
            self.framework = factory.new_framework(config.props)

            send_private(:setLogger)

            framework.init
            framework.start

            sl = framework.adapt(org.osgi.framework.startlevel.FrameworkStartLevel.java_class)
            sl.initial_bundle_start_level = config.defaultBundleStartlevel

            if framework.bundle_context.bundles.length == 1
              self.class.LOG.info("Installing and starting initial bundles")
              startup_props_file = java.io.File.new(config.karafEtc, self.class::STARTUP_PROPERTIES_FILE_NAME)
              bundles = read_bundles_from_startup_properties(startup_props_file)
              send_private(:installAndStartBundles, resolver, framework.bundle_context, bundles)
              self.class.LOG.info("All initial bundles installed and set to start")
            end

            server_info = org.apache.karaf.main.ServerInfoImpl.new(args, config)
            framework.bundle_context.register_service(org.apache.karaf.info.ServerInfo.java_class, server_info, nil)

            self.activatorManager = org.apache.karaf.main.KarafActivatorManager.new(classLoader, framework)

            # let the caller register services now that the framework is up,
            # but nothing is running yet
            yield framework.bundle_context

            set_start_level(config.defaultStartLevel)
          end
        end

        @main.launch_simple do
          # hook up the OSGI class loader manually
          @mutex.synchronize do
            ::JRuby.runtime.instance_config.add_loader(JRuby::OSGiBundleClassLoader.new(@main.framework))
          end

          @framework = @main.framework
          @bundle_context = @main.framework.bundle_context

          # prevent entirely blocked bundles from starting at all
          @main.framework.bundle_context.bundles.each do |b|
            sl = b.adapt(org.osgi.framework.startlevel.BundleStartLevel.java_class)
            sl.start_level = @main.config.defaultStartLevel + 1 if blocked_bundle?(b)
          end

          set_up_service_listener
          # replace event infrastructure with synchronous versions
          wait_for_service("org.osgi.service.event.EventAdmin") do |service|
            next if defined?(OpenHAB::Core::Mocks::EventAdmin) && service.is_a?(OpenHAB::Core::Mocks::EventAdmin)

            bundle = org.osgi.framework.FrameworkUtil.get_bundle(service.class)
            @mutex.synchronize do
              ::JRuby.runtime.instance_config.add_loader(JRuby::OSGiBundleClassLoader.new(bundle))
              require "rspec/openhab/core/mocks/event_admin"
              ea = OpenHAB::Core::Mocks::EventAdmin.new(@bundle_context)
              # we need to register it as if from the regular eventadmin bundle so other bundles
              # can properly find it
              bundle.bundle_context.register_service(
                org.osgi.service.event.EventAdmin.java_class,
                ea,
                java.util.Hashtable.new(org.osgi.framework.Constants::SERVICE_RANKING => 1.to_java(:int))
              )
            end
          end
          wait_for_service("org.openhab.core.karaf.internal.FeatureInstaller") do |fi|
            ca = ::OpenHAB::Core::OSGI.service("org.osgi.service.cm.ConfigurationAdmin")
            cfg = ca.get_configuration(org.openhab.core.OpenHAB::ADDONS_SERVICE_PID, nil)
            cfg.update(java.util.Hashtable.new) if cfg.properties.nil?
            fi.addAddon("automation", "jrubyscripting")
          end
          wait_for_service("org.openhab.core.automation.RuleManager") do |re|
            require "rspec/openhab/core/mocks/synchronous_executor"
            # overwrite thCallbacks to one that will spy to remove threading
            field = re.class.java_class.declared_field :thCallbacks
            field.accessible = true
            field.set(re, Core::Mocks::CallbacksMap.new)
            re.class.field_accessor :executor
            re.executor = Core::Mocks::SynchronousExecutor.instance
          end
        end
      end

      BLOCKED_COMPONENTS = {
        "org.openhab.core" => %w[
          org.openhab.core.addon.AddonEventFactory
          org.openhab.core.binding.BindingInfoRegistry
          org.openhab.core.binding.i18n.BindingI18nLocalizationService
          org.openhab.core.internal.auth.ManagedUserProvider
          org.openhab.core.internal.auth.UserRegistryImpl
        ].freeze,
        "org.openhab.core.automation.module.script.rulesupport" => %w[
          org.openhab.core.automation.module.script.rulesupport.internal.loader.DefaultScriptFileWatcher
        ].freeze,
        "org.openhab.core.binding.xml" => "org.openhab.core.binding.xml.internal.BindingXmlConfigDescriptionProvider",
        "org.openhab.core.config.core" => %w[
          org.openhab.core.config.core.internal.i18n.I18nConfigOptionsProvider
          org.openhab.core.config.core.status.ConfigStatusService
          org.openhab.core.config.core.status.events.ConfigStatusEventFactory
        ],
        "org.openhab.core.config.discovery" => nil,
        "org.openhab.core.config.dispatch" => nil,
        "org.openhab.core.io.net" => nil,
        "org.openhab.core.model.rule.runtime" => nil,
        "org.openhab.core.model.rule" => nil,
        "org.openhab.core.model.script" => %w[
          org.openhab.core.model.script.internal.RuleHumanLanguageInterpreter
          org.openhab.core.model.script.internal.engine.action.VoiceActionService
          org.openhab.core.model.script.jvmmodel.ScriptItemRefresher
        ].freeze,
        "org.openhab.core.model.sitemap.runtime" => nil,
        "org.openhab.core.voice" => nil,
        # the following bundles are blocked completely from starting
        "org.apache.karaf.http.core" => nil,
        "org.apache.karaf.shell.commands" => nil,
        "org.apache.karaf.shell.core" => nil,
        "org.apache.karaf.shell.ssh" => nil,
        "org.openhab.core.audio" => nil,
        "org.openhab.core.automation.module.media" => nil,
        "org.openhab.core.io.console" => nil,
        "org.openhab.core.io.http" => nil,
        "org.openhab.core.io.rest" => nil,
        "org.openhab.core.io.rest.core" => nil,
        "org.openhab.core.io.rest.sse" => nil,
        "org.openhab.core.model.lsp" => nil
      }.freeze
      private_constant :BLOCKED_COMPONENTS

      def set_up_bundle_listener
        wait_for_service("org.osgi.service.component.runtime.ServiceComponentRuntime") { |scr| @scr = scr }
        @bundle_context.add_bundle_listener do |event|
          bundle = event.bundle
          bundle_name = bundle.symbolic_name
          if event.type == org.osgi.framework.BundleEvent::INSTALLED
            sl = bundle.adapt(org.osgi.framework.startlevel.BundleStartLevel.java_class)
            sl.start_level = @main.config.defaultStartLevel + 1 if blocked_bundle?(bundle)
          end
          next unless event.type == org.osgi.framework.BundleEvent::STARTED

          @mutex.synchronize do
            ::JRuby.runtime.instance_config.add_loader(bundle)
          end

          # as soon as we _can_ do this, do it
          link_osgi if bundle.get_resource("org/slf4j/LoggerFactory.class")

          if @all_bundles_continue && all_bundles_started?
            @all_bundles_continue.call
            @all_bundles_continue = nil
          end

          if bundle_name == "org.openhab.core"
            require "rspec/openhab/core/mocks/bundle_resolver"
            bundle.bundle_context.register_service(
              org.openhab.core.util.BundleResolver.java_class,
              Core::Mocks::BundleResolver.instance,
              java.util.Hashtable.new(org.osgi.framework.Constants::SERVICE_RANKING => 1.to_java(:int))
            )
          end
          next unless BLOCKED_COMPONENTS.key?(bundle_name)

          components = BLOCKED_COMPONENTS[bundle_name]
          dtos = if components.nil?
                   @scr.get_component_description_dt_os(bundle)
                 else
                   Array(components).map { |component| @scr.get_component_description_dto(bundle, component) }
                 end
          dtos.each do |dto|
            @scr.disable_component(dto)
          end
        rescue Exception => e
          puts e.inspect
          puts e.backtrace
        end
        @bundle_context.bundles.each do |bundle|
          next unless bundle.symbolic_name.start_with?("org.openhab.core")

          @mutex.synchronize do
            ::JRuby.runtime.instance_config.add_loader(bundle)
          end
        end
      end

      def set_up_service_listener
        @awaiting_services = {}
        @bundle_context.add_service_listener do |event|
          next unless event.type == org.osgi.framework.ServiceEvent::REGISTERED

          ref = event.service_reference
          service = nil

          ref.get_property(org.osgi.framework.Constants::OBJECTCLASS).each do |klass|
            next unless @awaiting_services.key?(klass)

            service ||= @bundle_context.get_service(ref)
            @awaiting_services.delete(klass).call(service)
          end
        rescue Exception => e
          puts e.inspect
          puts e.backtrace
        end
      end

      def wait_for_service(service_name, &block)
        if defined?(::OpenHAB::Core::OSGI) &&
           (service = ::OpenHAB::Core::OSGI.service(service_name))
          return yield service
        end

        @awaiting_services[service_name] = block
      end

      def wait_for_start
        wait do |continue|
          @all_bundles_continue = continue
          next continue.call if all_bundles_started?
        end
      end

      def all_bundles_started?
        has_core = false
        result = @bundle_context.bundles.all? do |b|
          has_core = true if b.symbolic_name == "org.openhab.core"
          b.state == org.osgi.framework.Bundle::ACTIVE ||
            blocked_bundle?(b)
        end

        result && has_core
      end

      def blocked_bundle?(bundle)
        BLOCKED_COMPONENTS.fetch(bundle.symbolic_name, false).nil? ||
          bundle.symbolic_name.start_with?("org.eclipse.jetty") ||
          bundle.symbolic_name.start_with?("org.ops4j.pax.web") ||
          bundle.fragment?
      end

      def wait
        mutex = Mutex.new
        cond = ConditionVariable.new
        skip_wait = false

        continue = lambda do
          # if continue was called synchronously, we can just return
          next skip_wait = true if mutex.owned?

          mutex.synchronize { cond.signal }
        end
        mutex.synchronize do
          yield continue
          cond.wait(mutex) unless skip_wait
        end
      end

      def link_osgi
        ::OpenHAB::Core::OSGI.instance_variable_set(:@bundle, @framework) if require "openhab/core/osgi"
      end

      # import global variables and constants that openhab-scripting gem expects,
      # since we're going to be running it in this same VM
      def set_jruby_script_presets
        wait_for_service("org.openhab.core.automation.module.script.internal.ScriptExtensionManager") do |sem|
          # since we're not created by the ScriptEngineManager, this never gets set; manually set it
          $se = $scriptExtension = ScriptExtensionManagerWrapper.new(sem)
          scope_values = sem.find_default_presets("rspec")
          scope_values = scope_values.entry_set
          jrubyscripting = ::OpenHAB::Core::OSGI.services(
            "org.openhab.core.automation.module.script.ScriptEngineFactory",
            filter: "(service.pid=org.openhab.automation.jrubyscripting)"
          ).first

          %w[mapInstancePresets mapGlobalPresets].each do |method_name|
            method = jrubyscripting.class.java_class.get_declared_method(method_name, java.util.Map::Entry.java_class)

            method.accessible = true
            scope_values = scope_values.map { |e| method.invoke(nil, e) }
          end

          scope_values.each do |entry|
            key = entry.key
            value = entry.value
            # convert Java classes to Ruby classes
            value = value.ruby_class if value.is_a?(java.lang.Class) # rubocop:disable Lint/UselessAssignment
            # constants need to go into the global namespace
            key = "::#{key}" if ("A".."Z").cover?(key[0])
            eval("#{key} = value unless defined?(#{key})", nil, __FILE__, __LINE__) # rubocop:disable Security/Eval
          end
        end
      end

      # instance isn't part of the boot jars, but we need access to it
      # before we boot karaf in order to create the clone, so we have to
      # find it manually
      def find_karaf_instance_jar
        resolver = org.apache.karaf.main.util.SimpleMavenResolver.new([java.io.File.new("#{oh_runtime}/system")])
        slf4j = resolver.resolve(java.net.URI.new("mvn:org.ops4j.pax.logging/pax-logging-api/2.0.16"))
        version = find_boot_jar_version("org.apache.karaf.main")
        karaf_instance = resolver.resolve(java.net.URI.new(
                                            "mvn:org.apache.karaf.instance/org.apache.karaf.instance.core/#{version}"
                                          ))
        @karaf_instance_loader = java.net.URLClassLoader.new(
          [slf4j.to_url, karaf_instance.to_url].to_java(java.net.URL), ::JRuby.runtime.jruby_class_loader
        )
        ::JRuby.runtime.instance_config.add_loader(@karaf_instance_loader)
      end

      def find_boot_jar_version(bundle)
        prefix = "#{oh_runtime}/lib/boot/#{bundle}-"
        Dir["#{prefix}*.jar"].map { |jar| jar[prefix.length...-4] }.max
      end

      def load_boot_jars
        (Dir["#{oh_runtime}/lib/boot/*.jar"] +
        Dir["#{oh_runtime}/lib/endorsed/*.jar"] +
        Dir["#{oh_runtime}/lib/jdk9plus/*.jar"]).each do |jar|
          require jar
        end
      end

      def set_env
        ENV["DIRNAME"] = "#{oh_runtime}/bin"
        ENV["KARAF_HOME"] = oh_runtime
        Shell.source_env_from("#{oh_runtime}/bin/setenv")
      end

      def set_java_properties
        [ENV.fetch("JAVA_OPTS", nil), ENV.fetch("EXTRA_JAVA_OPTS", nil)].compact.each do |java_opts|
          Shellwords.split(java_opts).each do |arg|
            next unless arg.start_with?("-D")

            k, v = arg[2..].split("=", 2)
            java.lang.System.set_property(k, v)
          end
        end
      end

      # we can't set Java ENV directly, so we have to try and set some things
      # as system properties
      def set_java_properties_from_env
        ENV.each do |(k, v)|
          next unless k.match?(/^(?:KARAF|OPENHAB)_/)

          prop = k.downcase.tr("_", ".")
          next unless java.lang.System.get_property(prop).nil?

          java.lang.System.set_property(prop, v)
        end
      end

      def oh_home
        @oh_home ||= ENV.fetch("OPENHAB_HOME", "/usr/share/openhab")
      end

      def oh_runtime
        @oh_runtime ||= ENV.fetch("OPENHAB_RUNTIME", "#{oh_home}/runtime")
      end

      def cleanup_clone
        FileUtils.rm_rf(["#{path}/cache",
                         "#{path}/config/org/apache/felix/fileinstall",
                         "#{path}/jsondb/backup",
                         "#{path}/marketplace",
                         "#{path}/log/*",
                         "#{path}/tmp/*",
                         "#{path}/jsondb/org.openhab.marketplace.json",
                         "#{path}/jsondb/org.openhab.jsonaddonservice.json",
                         "#{path}/config/org/openhab/jsonaddonservice.config",
                         "#{path}/config/org/openhab/addons.config"])
      end

      def prune_startlevels
        startlevels = File.read("#{path}/config/org/openhab/startlevel.config")
        startlevels.sub!(",rules:refresh,rules:dslprovider", "")
        File.write("#{path}/config/org/openhab/startlevel.config", startlevels)
      end

      def minimize_installed_features
        # cuts down openhab-runtime-base significantly (importantly,
        # including the OpenHAB karaf FeatureInstaller), makes sure
        # openhab-runtime-ui doesn't get installed (from profile.cfg),
        # double-makes-sure no addons get installed, and marks several
        # bundles to not actually start, even though they must still be
        # installed to meet dependencies
        File.write("#{path}/etc/org.apache.karaf.features.xml", <<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <featuresProcessing xmlns="http://karaf.apache.org/xmlns/features-processing/v1.0.0" xmlns:f="http://karaf.apache.org/xmlns/features/v1.6.0">
              <blacklistedFeatures>
                <feature>openhab-runtime-ui</feature>
                <feature>*-binding-*</feature>
                <!--<feature>openhab-automation-*</feature>-->
                <feature>openhab-core-io-*</feature>
                <feature>openhab-core-ui*</feature>
                <feature>openhab-misc-*</feature>
                <feature>openhab-persistence-*</feature>
                <feature>openhab-package-standard</feature>
                <feature>openhab-ui-*</feature>
                <feature>openhab-voice-*</feature>
              </blacklistedFeatures>
              <featureReplacements>
                <replacement mode="replace">
                  <feature name="openhab-runtime-base" version="3.4.0.SNAPSHOT">
                    <f:feature>openhab-core-base</f:feature>
                    <f:feature>openhab-core-automation-module-script</f:feature>
                    <f:feature>openhab-core-automation-module-script-rulesupport</f:feature>
                    <f:feature>openhab-core-automation-module-media</f:feature>
                    <f:feature>openhab-core-model-item</f:feature>
                    <f:feature>openhab-core-model-persistence</f:feature>
                    <f:feature>openhab-core-model-rule</f:feature>
                    <f:feature>openhab-core-model-script</f:feature>
                    <f:feature>openhab-core-model-sitemap</f:feature>
                    <f:feature>openhab-core-model-thing</f:feature>
                    <f:feature>openhab-core-storage-json</f:feature>
                    <f:feature>openhab-automation-jrubyscripting</f:feature>
                  </feature>
                </replacement>
              </featureReplacements>
          </featuresProcessing>
        XML
      end
    end
  end
end
