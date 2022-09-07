# frozen_string_literal: true

require "singleton"

module RSpec
  module OpenHAB
    module Core
      module Mocks
        class CallbacksMap < java.util.HashMap
          def put(_rule_uid, trigger_handler)
            trigger_handler.executor.shutdown_now
            trigger_handler.executor = SynchronousExecutor.instance
            super
          end
        end

        class SynchronousExecutor
          include java.util.concurrent.ScheduledExecutorService
          include Singleton

          def submit(runnable)
            runnable.respond_to?(:run) ? runnable.run : runnable.call

            java.util.concurrent.CompletableFuture.completed_future(nil)
          end

          def execute(runnable)
            runnable.run
          end

          def shutdown; end
          def shutdown_now; end

          def shutdown?
            false
          end
        end
      end
    end
  end
end
