# frozen_string_literal: true

RSpec.configure do |config|
  def quiesce
    suspend_rules do
      OpenHAB::DSL::Timers.timer_manager.cancel_all
      # it's possible that a timer started executing
      # right after canceling, and scheduled a future timer
      # so wait for it to finish running
      wait_for_background_tasks(future_timers: false)
      # then cancel them all again
      OpenHAB::DSL::Timers.timer_manager.cancel_all
    end
  end

  config.after(:each) { quiesce }
end
