# frozen_string_literal: true

module RSpec
  module OpenHAB
    module JRuby
      # Basically org.jruby.embed.osgi.OSGiIsolatedScriptingContainter$BundleGetResources,
      # but implemented in Ruby so that it doesn't have a hard dependency on
      # org.osgi.bundle.Bundle -- which we may need to load!
      class OSGiBundleClassLoader
        include org.jruby.util.Loader

        def initialize(bundle)
          @bundle = bundle
        end

        def get_resource(path)
          @bundle.get_resource(path)
        end

        def get_resources(path)
          @bundle.get_resources(path)
        end

        def load_class(name)
          @bundle.load_class(name)
        end

        def get_class_loader # rubocop:disable Naming/AccessorMethodName
          org.jruby.embed.osgi.internal.BundleWiringOSGiClassLoaderAdapter.new.get_class_loader(@bundle)
        end
      end

      module InstanceConfig
        def add_loader(loader)
          # have to use Ruby-style class reference for the defined? check
          if defined?(Java::OrgOsgiFramework::Bundle) && loader.is_a?(org.osgi.framework.Bundle)
            loader = OSGiBundleClassLoader.new(loader)
          end
          super(loader)
        end
      end
      org.jruby.RubyInstanceConfig.prepend(InstanceConfig)
    end
  end
end