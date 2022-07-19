# frozen_string_literal: true

module OpenHAB
  module Core
    class OSGI
      class << self
        def register_service(name, service = nil)
          if service.nil?
            service = name
            name = service.java_class.interfaces.first&.name || service.java_class.name
          end
          (@services ||= {})[name] = service
        end

        def service(name)
          @services&.[](name)
        end

        def services(name, filter: nil); end
      end
    end
  end
end
