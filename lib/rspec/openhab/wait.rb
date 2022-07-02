# frozen_string_literal: true

module RSpec
  module OpenHAB
    module Wait
      def wait_for_rules
        wait_for_background_tasks(timers: false)
      end

      def wait_for_timers
        wait_for_background_tasks(rules: false)
      end

      def wait_for_background_tasks(rules: true, timers: true)
        loop do
          sleep 0.1
          next if java.lang.Thread.all_stack_traces.any? do |(t, stack)|
            # this is just an estimate. I see 9 when it's parked waiting
            # for an event, but once it hits ruby it gets real big real quick
            min_frames = 15

            case t.name
            when /^OH-scheduler-/
              # timer thread; born and die for each timer
              if thread_running?(t) || stack.length > min_frames
                logger.debug "thread #{t.name} is running (#{stack.length})"
                stack.each do |frame|
                  logger.trace "  #{frame}"
                end
                next timers
              end
            when /^OH-rule-/

              if thread_running?(t) || stack.length > min_frames
                logger.debug "thread #{t.name} is running (#{stack.length})"
                stack.each do |frame|
                  logger.trace "  #{frame}"
                end

                next rules
              end
            when /^OH-(?:eventwatcher|eventexecutor)-/
              # an event is making its way through the system
              if thread_running?(t)
                logger.debug "thread #{t.name} is running"
                next rules
              end
            end
          end

          # no need to retry if there were no timers
          break unless timers && wait_for_next_timer
        end
      end

      private

      def thread_running?(thread)
        ![java.lang.Thread::State::WAITING,
          java.lang.Thread::State::TIMED_WAITING].include?(thread.state)
      end

      def wait_for_next_timer
        latest = ::OpenHAB::DSL::Timers.timer_manager.instance_variable_get(:@timers).min_by(&:execution_time)
        return false unless latest

        delta = (latest.execution_time.to_instant.to_epoch_milli - java.time.Instant.now.to_epoch_milli) / 1000.0
        # in the past? it's probably executing
        return true if delta.negative?

        logger.info("Waiting #{delta}s for next timer") if delta > 5

        sleep(delta)
        true
      end
    end
  end
end

RSpec.configure do |config|
  config.include RSpec::OpenHAB::Wait
end
