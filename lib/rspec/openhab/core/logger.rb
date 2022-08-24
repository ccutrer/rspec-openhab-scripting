# frozen_string_literal: true

module OpenHAB
  module Core
    class Logger
      class << self
        def log_service
          @log_service = OSGI.service("org.apache.karaf.log.core.LogService")
        end
      end

      def level=(level)
        self.class.log_service.set_level(@sl4fj_logger.name, level.to_s)
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
