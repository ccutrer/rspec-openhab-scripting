# frozen_string_literal: true

def ch
  Java::Ch
end

ch.qos.logback.classic.Level.class_eval do
  alias_method :inspect, :to_s
end

module OpenHAB
  module Core
    class Logger
      levels = %i[OFF ERROR WARN INFO DEBUG TRACE ALL]
      levels.each { |level| const_set(level, ch.qos.logback.classic.Level.const_get(level)) }

      extend Forwardable
      delegate %i[level level=] => :@sl4fj_logger
    end
  end
end

root_logger = org.slf4j.LoggerFactory.get_logger(org.slf4j.Logger::ROOT_LOGGER_NAME)
root_logger.level = OpenHAB::Core::Logger::INFO
