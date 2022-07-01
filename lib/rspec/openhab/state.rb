# frozen_string_literal: true

RSpec.configure do |config|
  org.openhab.core.items.GenericItem.field_reader :eventPublisher

  config.before(:each) do
    ep = $ir.eventPublisher

    # stash event publishers to avoid triggering any rules
    $ir.for_each do |_provider, item|
      item.event_publisher = nil
    end

    $ir.for_each do |_provider, item| # rubocop:disable Style/CombinableLoops
      item.state = NULL # don't use update, to avoid triggering any rules
    end
  ensure
    $ir.for_each do |_provider, item|
      item.event_publisher = ep
    end
  end
end
