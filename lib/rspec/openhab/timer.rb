# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each) do
    OpenHAB::DSL::Timers.timer_manager.cancel_all
  end
  config.after(:each) do
    OpenHAB::DSL::Timers.timer_manager.cancel_all
  end
end
