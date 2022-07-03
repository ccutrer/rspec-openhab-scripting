# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:all) { OpenHAB::DSL::Timers.timer_manager.cancel_all }
  config.after(:each) do
    OpenHAB::DSL::Timers.timer_manager.cancel_all
    Timecop.return
  end
end
