# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each) do
    OpenHAB::DSL::Timers.timer_manager.cancel_all
    wait_for_background_tasks
  end
  config.after(:each) do
    OpenHAB::DSL::Timers.timer_manager.cancel_all
    wait_for_background_tasks
  end
end
