# frozen_string_literal: true

module OpenHAB
  module DSL
    class Timer
      #
      # Create a new Timer Object
      #
      # @param [Duration] duration Duration until timer should fire
      # @param [Block] block Block to execute when timer fires
      #
      def initialize(duration:, thread_locals: {}, &block) # rubocop:disable Lint/UnusedMethodArgument
        @duration = duration

        Timers.timer_manager.add(self)
      end

      def reschedule(duration = nil)
        duration ||= @duration

        Timers.timer_manager.add(self)
        reschedule(OpenHAB::DSL.to_zdt(duration))
      end

      #
      # Cancel timer
      #
      # @return [Boolean] True if cancel was successful, false otherwise
      #
      def cancel
        Timers.timer_manager.delete(self)
      end

      def terminated?; end
      alias_method :has_terminated, :terminated?

      private

      def timer_block
        proc do
          Timers.timer_manager.delete(self)
          yield(self)
        end
      end
    end

    #
    # Convert TemporalAmount (Duration), seconds (float, integer), and Ruby Time to ZonedDateTime
    # Note: TemporalAmount is added to now
    #
    # @param [Object] timestamp to convert
    #
    # @return [ZonedDateTime]
    #
    def self.to_zdt(timestamp)
      logger.trace("Converting #{timestamp} (#{timestamp.class}) to ZonedDateTime")
      return unless timestamp

      case timestamp
      when Java::JavaTimeTemporal::TemporalAmount then ZonedDateTime.now.plus(timestamp)
      when ZonedDateTime then timestamp
      when Time then timestamp.to_java(ZonedDateTime)
      else
        to_zdt(seconds_to_duration(timestamp)) ||
          raise(ArgumentError, "Timestamp must be a ZonedDateTime, a Duration, a Numeric, or a Time object")
      end
    end

    #
    # Convert numeric seconds to a Duration object
    #
    # @param [Float, Integer] secs The number of seconds in integer or float
    #
    # @return [Duration]
    #
    def self.seconds_to_duration(secs)
      return unless secs

      if secs.respond_to?(:to_f)
        secs.to_f.seconds
      elsif secs.respond_to?(:to_i)
        secs.to_i.seconds
      end
    end
  end
end
