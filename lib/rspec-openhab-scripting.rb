# frozen_string_literal: true

# see https://github.com/jruby/jruby/issues/7262
# in the meantime, I've "vendored" it, and just forcing it on the load path first
$LOAD_PATH.unshift(File.expand_path("../vendor/gems/jar-dependencies-1.0.0/lib", __dir__))

require "rspec/openhab/api"
api = OpenHAB::API.new("http://#{ENV.fetch("OPENHAB_HOST", "localhost")}:#{ENV.fetch("OPENHAB_HTTP_PORT", "8080")}/",
                       ENV.fetch("OPENHAB_TOKEN", nil))

module OpenHAB
  module Core
    class << self
      attr_accessor :openhab_version
    end
  end
end

oh_home = ENV.fetch("OPENHAB_HOME", "/usr/share/openhab")
oh_runtime = ENV.fetch("OPENHAB_RUNTIME", "#{oh_home}/runtime")

ENV["JARS_ADDITIONAL_MAVEN_REPOS"] = File.join(oh_runtime, "system")

openhab_version = OpenHAB::Core.openhab_version = api.version

require "rspec-openhab-scripting_jars"

maven_require do
  # upstream dependencies that I don't know how to infer from the openhab bundles alone
  require "jar com.google.code.gson, gson, 2.8.9"
  require "jar org.eclipse.xtext, org.eclipse.xtext, 2.26.0"
  require "jar org.osgi, osgi.cmpn, 7.0.0"
  require "jar org.osgi, org.osgi.framework, 1.8.0"
  require "jar si.uom, si-units, 2.1"
  require "jar tech.units, indriya, 2.1.3"

  require "jar org.openhab.core.bundles, org.openhab.core, #{openhab_version}"
  require "jar org.openhab.core.bundles, org.openhab.core.automation, #{openhab_version}"
  require "jar org.openhab.core.bundles, org.openhab.core.automation.module.script, #{openhab_version}"
  require "jar org.openhab.core.bundles, org.openhab.core.automation.module.script.rulesupport, #{openhab_version}"
  require "jar org.openhab.core.bundles, org.openhab.core.config.core, #{openhab_version}"
  require "jar org.openhab.core.bundles, org.openhab.core.io.monitor, #{openhab_version}"
  require "jar org.openhab.core.bundles, org.openhab.core.model.core, #{openhab_version}"
  require "jar org.openhab.core.bundles, org.openhab.core.model.item, #{openhab_version}"
  require "jar org.openhab.core.bundles, org.openhab.core.model.script, #{openhab_version}"
  require "jar org.openhab.core.bundles, org.openhab.core.persistence, #{openhab_version}"
  require "jar org.openhab.core.bundles, org.openhab.core.semantics, #{openhab_version}"
  require "jar org.openhab.core.bundles, org.openhab.core.thing, #{openhab_version}"
end
java_import org.openhab.core.persistence.extensions.PersistenceExtensions

require "openhab/version"

# we completely override some files from openhab-scripting
$LOAD_PATH.unshift("#{__dir__}/rspec")

oh = org.openhab.core.OpenHAB
def oh.config_folder
  ENV.fetch("OPENHAB_CONF", "/etc/openhab")
end

# global variables need to be set up before openhab-scripting loads
require "timecop"
require "openhab/log/logger"
require "rspec/openhab/core/logger"

# during testing, we don't want "regular" output from rules
OpenHAB::Log.logger("org.openhab.automation.jruby.runtime").level = :warn
OpenHAB::Log.logger("org.openhab.automation.jruby.logger").level = :warn
require "rspec/openhab/core/mocks/channel_type_provider"
require "rspec/openhab/core/mocks/item_channel_link_provider"
require "rspec/openhab/core/mocks/persistence_service"
require "rspec/openhab/core/mocks/thing_handler"
require "rspec/openhab/core/mocks/thing_type_provider"
require "openhab/dsl/imports"
OpenHAB::DSL::Imports.api = api
OpenHAB::DSL::Imports.import_presets

require "openhab"

require "rspec/openhab/actions"
require "rspec/openhab/core/cron_scheduler"

# override several openhab-scripting methods
require_relative "rspec/openhab/core/item_proxy"
require_relative "rspec/openhab/dsl/timers/timer"
require_relative "rspec/openhab/dsl/rules/triggers/watch"

# RSpec additions
require "rspec/core"
require "rspec/openhab/helpers"
require "rspec/openhab/hooks"
require "rspec/openhab/suspend_rules"

RSpec.configure do |config|
  config.include OpenHAB::Core::EntityLookup
end

# make bundler/inline _not_ destroy the already existing load path
module Bundler
  module SharedHelpers
    def clean_load_path; end
  end
end
