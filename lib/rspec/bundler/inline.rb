# frozen_string_literal: true

module Bundler
  class DummyDsl
    def source(*); end
  end
end

def gemfile(*, &block)
  # needs to be a no-op, since we're already running in the context of bundler
  Bundler::DummyDsl.new.instance_eval(&block)
end
