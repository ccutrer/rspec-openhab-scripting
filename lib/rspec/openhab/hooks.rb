# frozen_string_literal: true

RSpec.configure do |config|
  config.before do
    suspend_rules do
      $ir.for_each do |_provider, item|
        next if item.is_a?(GroupItem) # groups only have calculated states

        item.state = NULL unless item.raw_state == NULL
      end
    end
  end
  config.after do
    OpenHAB::DSL::Timers.timer_manager.cancel_all
    Timecop.return
    restore_autoupdate_items
  end
end
