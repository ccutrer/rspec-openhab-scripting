# frozen_string_literal: true

require "openssl"
require "shellwords"

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
      rescue Exception => e
        puts e.inspect
        puts e.backtrace
        raise
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
        minimize_installed_features
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
        java.lang.System.set_property("openhab.logdir", "#{path}/log")
        # we don't need a shutdown socket
        java.lang.System.set_property("karaf.shutdown.port", "-1")
        # disable HTTP
        java.lang.System.set_property("org.osgi.service.http.enabled", "false")
        java.lang.System.set_property("org.osgi.service.http.secure.enabled", "false")
        # for some reason it still tries to launch a secure server; prevent
        # it from succeeding (and mute the log entry)
        java.lang.System.set_property("org.osgi.service.http.port.secure", "-1")
        java.lang.System.set_property("log4j2.logger.org.ops4j.pax.web.service.internal.HttpServiceStarted.level",
                                      "off")
        # ensure we're not logging to stdout
        java.util.logging.LogManager.log_manager.reset

        # launch it! (don't use Main.main; it will wait for it to be
        # shut down externally)
        main = org.apache.karaf.main.Main.new([])
        main.launch
        at_exit { main.destroy }
        @framework = main.framework
        @bundle_context = main.framework.bundle_context
        # hook up the OSGI class loader manually
        ::JRuby.runtime.instance_config.add_loader(JRuby::OSGiBundleClassLoader.new(main.framework))
        # automatically shut it down when Ruby wants to be done
        link_osgi
        set_up_service_listener
        set_up_bundle_listener
        silence_pax
        wait_for_start
        set_jruby_script_presets
        main
      end

      def silence_pax
        wait_for_service("org.apache.karaf.log.core.LogService") do |log_service|
          log_service.set_level("org.ops4j.pax.web.service.internal.HttpServiceStarted", "FATAL")
        end
      end

      def set_up_bundle_listener
        @bundle_context.add_bundle_listener do |event|
          next unless event.type == org.osgi.framework.BundleEvent::STARTING
          next unless event.bundle.symbolic_name.start_with?("org.openhab.core")

          ::JRuby.runtime.instance_config.add_loader(event.bundle)
        end
        @bundle_context.bundles.each do |bundle|
          next unless bundle.symbolic_name.start_with?("org.openhab.core")

          ::JRuby.runtime.instance_config.add_loader(bundle)
        end
      end

      def set_up_service_listener
        @awaiting_services = {}
        @bundle_context.add_service_listener do |event|
          next unless event.type == org.osgi.framework.ServiceEvent::REGISTERED

          ref = event.service_reference
          service = nil

          ref.get_property("objectClass").each do |klass|
            next unless @awaiting_services.key?(klass)

            service ||= @bundle_context.get_service(ref)
            @awaiting_services.delete(klass).call(service)
          end
        end
      end

      def wait_for_service(service_name, &block)
        @awaiting_services[service_name] = block
      end

      def wait_for_start
        mutex = Mutex.new
        cond = ConditionVariable.new

        @bundle_context.add_framework_listener do |event|
          next unless event.type == org.osgi.framework.FrameworkEvent::STARTLEVEL_CHANGED

          mutex.synchronize { cond.signal }
        end

        mutex.synchronize { cond.wait(mutex) }
      end

      # require this right away, so that we can access OSGI services easily
      def link_osgi
        require "openhab/core/osgi"
        ::OpenHAB::Core::OSGI.instance_variable_set(:@bundle, @framework)
      end

      # import global variables and constants that openhab-scripting gem expects,
      # since we're going to be running it in this same VM
      def set_jruby_script_presets
        # since we're not created by the ScriptEngineManager, this never gets set; manually set it
        sem = ::OpenHAB::Core::OSGI.service("org.openhab.core.automation.module.script.internal.ScriptExtensionManager")
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

      # instance isn't part of the boot jars, but we need access to it
      # before we boot karaf in order to create the clone, so we have to
      # find it manually
      def find_karaf_instance_jar
        resolver = org.apache.karaf.main.util.SimpleMavenResolver.new([java.io.File.new("#{oh_runtime}/system")])
        slf4j = resolver.resolve(java.net.URI.new("mvn:org.ops4j.pax.logging/pax-logging-api/2.0.16"))
        require slf4j.path
        version = find_boot_jar_version("org.apache.karaf.main")
        karaf_instance = resolver.resolve(java.net.URI.new(
                                            "mvn:org.apache.karaf.instance/org.apache.karaf.instance.core/#{version}"
                                          ))
        require karaf_instance.path
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
