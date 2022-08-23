# this is a generated file, to avoid over-writing it just delete this comment
begin
  require 'jar_dependencies'
rescue LoadError
  require 'ch/qos/logback/logback-classic/1.2.9/logback-classic-1.2.9.jar'
  require 'org/slf4j/slf4j-api/1.7.32/slf4j-api-1.7.32.jar'
  require 'ch/qos/logback/logback-core/1.2.9/logback-core-1.2.9.jar'
end

if defined? Jars
  #require_jar 'ch.qos.logback', 'logback-classic', '1.2.9'
  require_jar 'org.slf4j', 'slf4j-api', '1.7.32'
  #require_jar 'ch.qos.logback', 'logback-core', '1.2.9'
end
