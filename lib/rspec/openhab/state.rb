# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each) do
    $ir.for_each do |_provider, item| # rubocop:disable Style/GlobalVars
      item.state = NULL # don't use update, to avoid triggering any rules
    end
  end
end
