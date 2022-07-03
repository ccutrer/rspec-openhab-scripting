# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each) do
    suspend_rules do
      $ir.for_each do |_provider, item|
        item.state = NULL
      end
    end
  end
end
