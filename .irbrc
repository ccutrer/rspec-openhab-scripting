# frozen_string_literal: true

require "rubygems"
require "bundler"

# it's useless with so many java objects
IRB.conf[:USE_AUTOCOMPLETE] = false

Object.include RSpec::OpenHAB::Helpers
launch_karaf(include_bindings: false, include_jsondb: false, private_confdir: true)
