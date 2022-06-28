# frozen_string_literal: true

Bundler::FriendlyErrors.disable!

require "rspec/openhab/api"
api = OpenHAB::API.new("http://#{ENV.fetch("OPENHAB_HOST", "localhost")}:#{ENV.fetch("OPENHAB_HTTP_PORT", "8080")}/")

module OpenHAB
  module Core
    class << self
      attr_accessor :openhab_version
    end
  end
end

openhab_version = OpenHAB::Core.openhab_version = api.version

require "rspec-openhab-scripting_jars"
require_jar "org.osgi", "org.osgi.util.tracker", "1.5.4"
require_jar "org.openhab.core.bundles", "org.openhab.core", openhab_version
require_jar "org.openhab.core.bundles", "org.openhab.core.config.core", openhab_version
require_jar "org.openhab.core.bundles", "org.openhab.core.automation", openhab_version
require_jar "org.openhab.core.bundles", "org.openhab.core.automation.module.script", openhab_version
require_jar "org.openhab.core.bundles", "org.openhab.core.automation.module.script.rulesupport", openhab_version
require_jar "org.openhab.core.bundles", "org.openhab.core.model.core", openhab_version
require_jar "org.openhab.core.bundles", "org.openhab.core.model.script", openhab_version
require_jar "org.openhab.core.bundles", "org.openhab.core.semantics", openhab_version
require_jar "org.openhab.core.bundles", "org.openhab.core.test", openhab_version
require_jar "org.openhab.core.bundles", "org.openhab.core.thing", openhab_version

require "openhab/version"

# we completely override some files from openhab-scripting
$LOAD_PATH.unshift("#{__dir__}/rspec")

oh = org.openhab.core.OpenHAB
def oh.config_folder
  ENV.fetch("OPENHAB_CONF", "/etc/openhab")
end

# global variables need to be set up before openhab-scripting loads
require "openhab/log/logger"
require "rspec/openhab/core/logger"
require "openhab/dsl/imports"
OpenHAB::DSL::Imports.import_presets

require "openhab"

require "rspec/openhab/core/cron_scheduler"

# openhab-scripting uses a require_relative, so our override doesn't get used
OpenHAB::DSL.send(:remove_const, :Timer)
require_relative "rspec/openhab/dsl/timers/timer"

# rubocop:disable Style/GlobalVars

# populate item registry
all_items = api.items
all_items.each do |item_json|
  type, _dimension = item_json["type"].split(":")
  if type == "Group"
    if item_json["groupType"]
      type, _dimension = item_json["groupType"].split(":")
      klass = OpenHAB::DSL::Items.const_get(:"#{type}Item")
      base_item = klass.new(item_json["name"])
    end
    # TODO: create group function
    item = GroupItem.new(item_json["name"], base_item)
  else
    klass = OpenHAB::DSL::Items.const_get(:"#{type}Item")
    item = klass.new(item_json["name"])
  end

  item.label = item_json["label"]
  item_json["tags"].each do |tag|
    item.add_tag(tag)
  end
  $ir.add(item)
end
all_items.each do |item_json| # rubocop:disable Style/CombinableLoops
  item_json["groupNames"].each do |group_name|
    next unless (group = $ir.get(group_name))

    group.add_member($ir.get(item_json["name"]))
  end
end

# rubocop:enable Style/GlobalVars

# load rules files
OPENHAB_AUTOMATION_PATH = "#{org.openhab.core.OpenHAB.config_folder}/automation/jsr223/ruby/personal"

require "bundler/inline"

# set up some environment the rules files expect
Bundler.with_unbundled_env do
  Dir["#{OPENHAB_AUTOMATION_PATH}/*.rb"].each do |f|
    load f
  rescue => e
    warn "Failed loading #{f}: #{e}"
    warn e.backtrace
  end
end
