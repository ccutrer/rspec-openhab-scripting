# frozen_string_literal: true

require_relative "lib/rspec/openhab/version"

Gem::Specification.new do |s|
  s.name = "rspec-openhab-scripting"
  s.version = RSpec::OpenHAB::VERSION
  s.platform = "java"
  s.authors = ["Cody Cutrer"]
  s.email = "cody@cutrer.us'"
  s.homepage = "https://github.com/ccutrer/rspec-openhab-scripting"
  s.summary = "Library testing OpenHAB ruby rules with rspec."
  s.license = "MIT"
  s.metadata = {
    "rubygems_mfa_required" => "true"
  }

  s.requirements << "jar ch.qos.logback, logback-classic, 1.2.9"

  s.files = Dir["{lib,vendor}/**/*"]

  s.required_ruby_version = ">= 2.6"

  s.add_dependency "faraday", "~> 2.3"
  s.add_dependency "jar-dependencies", "~> 0.4"
  s.add_dependency "net-http-persistent", "~> 4.0"
  s.add_dependency "openhab-scripting", "~> 4.42"
  s.add_dependency "rspec-core", "~> 3.11"
  s.add_dependency "ruby-maven", "~> 3.3"
  s.add_dependency "timecop", "~> 0.9"

  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "rubocop", "~> 1.23"
  s.add_development_dependency "rubocop-performance", "~> 1.12"
  s.add_development_dependency "rubocop-rake", "~> 0.6"
  s.add_development_dependency "ruby-debug", "~> 0.11"
end
