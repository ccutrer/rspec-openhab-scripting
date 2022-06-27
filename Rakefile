# frozen_string_literal: true

begin
  require "bundler/setup"
rescue LoadError
  puts "You must `gem install bundler` and `bundle install` to run rake tasks"
end

Bundler::GemHelper.install_tasks

require "jars/installer"
desc "Generate _jars.rb file"
task :install_jars do
  Jars::Installer.vendor_jars!
end
