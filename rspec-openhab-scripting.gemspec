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

  s.requirements << "jar com.google.code.gson, gson, 2.8.9"
  s.requirements << "jar org.eclipse.xtext, org.eclipse.xtext, 2.26.0"
  s.requirements << "jar org.osgi, osgi.cmpn, 7.0.0"
  s.requirements << "jar org.osgi, org.osgi.framework, 1.8.0"
  s.requirements << "jar org.slf4j, slf4j-simple, 1.7.35"
  s.requirements << "jar si.uom, si-units, 2.1"
  s.requirements << "jar tech.units, indriya, 2.1.3"

  s.files = Dir["{lib}/**/*"]

  s.required_ruby_version = ">= 2.5"

  s.add_dependency "faraday_middleware", "~> 1.1"
  s.add_dependency "net-http-persistent", "~> 4.0"
  s.add_dependency "openhab-scripting", "~> 4.42"
  s.add_runtime_dependency "jar-dependencies", "~> 0.4"

  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "rubocop", "~> 1.23"
  s.add_development_dependency "rubocop-performance", "~> 1.12"
  s.add_development_dependency "rubocop-rake", "~> 0.6"
end
