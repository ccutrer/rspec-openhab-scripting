# frozen_string_literal: true

module OpenHAB
  module Core
    class CronScheduler
      include Singleton

      def schedule(*); end
    end

    OpenHAB::Core::OSGI.register_service("org.openhab.core.scheduler.CronScheduler", CronScheduler.instance)
  end
end
