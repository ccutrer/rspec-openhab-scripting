# frozen_string_literal: true

# we completely override some files from openhab-scripting
$LOAD_PATH.unshift("#{__dir__}/rspec")

require "diff/lcs"

require "rspec/openhab/helpers"
require "rspec/openhab/karaf"
require "rspec/openhab/hooks"
