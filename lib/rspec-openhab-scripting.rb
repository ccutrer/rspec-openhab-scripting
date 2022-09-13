# frozen_string_literal: true

require "openhab/version"

unless RUBY_ENGINE == "jruby" &&
       Gem::Version.new(RUBY_ENGINE_VERSION) >= Gem::Version.new("9.3.8.0")
  raise Gem::RubyVersionMismatch, "rspec-openhab-scripting requires JRuby 9.3.8.0 or newer"
end

# we completely override some files from openhab-scripting
$LOAD_PATH.unshift("#{__dir__}/rspec")

require "diff/lcs"

require "rspec/openhab/helpers"
require "rspec/openhab/karaf"
require "rspec/openhab/hooks"
