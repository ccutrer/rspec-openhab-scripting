# frozen_string_literal: true

require "jruby"

# helper method to load a JAR from within a KAR
def require_kar(kar_path, *jar_args)
  jar_path = Jars.send(:to_jar, *jar_args)
  JRuby.runtime.jruby_class_loader.add_url(java.net.URL.new("jar:file://#{kar_path}!/repository/#{jar_path}"))
end
