# frozen_string_literal: true

module OpenHAB
  module DSL
    module Items
      class GenericItem
        def command(command)
          command = format_type_pre(command)
          logger.trace "Sending Command #{command} to #{id}"
          # TODO: parse type
          # TODO: assign state
          # TODO: trigger rules
          self
        end

        def updates(update)
          update = format_type_pre(update)
          logger.trace "Sending update #{update} to #{id}"
          # TODO: parse type
          # TODO: assign state
          # TODO: trigger rules
          self
        end
      end
    end
  end
end
