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
      delegate %i[level] => :@sl4fj_logger

      def level=(level)
        if level.is_a?(String) || level.is_a?(Symbol)
          level = ch.qos.logback.classic.Level.const_get(level.to_s.upcase, false)
        end
        @sl4fj_logger.level = level
      end
    end
  end

  module Log
    class << self
      def root
        logger(org.slf4j.Logger::ROOT_LOGGER_NAME)
      end

      def events
        logger("openhab.event")
      end

      def logger(object)
        logger_name = case object
                      when String then object
                      else logger_name(object)
                      end
        @loggers[logger_name] ||= Core::Logger.new(logger_name)
      end
    end
  end
end

OpenHAB::Log.root.level = :info
OpenHAB::Log.events.level = :warn
