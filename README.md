# rspec-openhab-scripting

This gem allows you to write unit tests for your OpenHAB rules written in
JRuby. It loads up a limited actual OpenHAB runtime environment. Because it is
a limited environment, with no actual bindings or things, you may need to stub
out those actions in your tests. The autoupdate manager is running, so any
commands sent to items that aren't marked as `autoupdate="false"` will update
automatically.

## Usage

You must run tests on a system with actual OpenHAB instance installed, with your
configuration. JRuby >= 9.3.8.0 must also be installed.

 * Install and activate JRuby (by your method of choice - chruby, rbenv, etc.).
 * Either create an empty directory, or use `$OPENHAB_CONF` itself (the former
   is untested)
 * Create a `Gemfile` with the following contents (or add to an existing one):
```ruby
source "https://rubygems.org"

group(:test) do
  gem "rspec", "~> 3.11"
  gem "rspec-openhab-scripting", "~> 0.0.1"
end

group(:rules) do
  # include any gems you reference from `gemfile` calls in your rules so that
  # they'll already be available in the rules, and won't need to be
  # re-installed on every run, slowing down spec runs considerably
end
```
 * Run `gem install bundler`
 * Run `bundle install`
 * Run `bundle exec rspec --init`
 * Edit the generated `spec/spec_helper.rb` to satisfy your preferences, and
 add:
```ruby
require "rubygems"
require "bundler"

Bundler.require(:default, :test)

# if you have any automatic requires setup in jrubyscripting's config,
# (besides `openhab`), you need to manually require them here
```
 * Create some specs! An example of `spec/switches_spec.rb`:
```ruby
RSpec.describe "switches.rb" do
  describe "gFullOn" do
    it "works" do
      GuestCans_Dimmer.update(0)
      GuestCans_Scene.update(1.3)
      expect(GuestCans_Dimmer.state).to eq 100
    end

    it "sets some state" do
      trigger_rule("my rule")
      expect(GuestCans_Scene.state).to be_nil
    end

    it "triggers a rule expecting an event" do
      trigger_rule("my rule 2", Struct.new(:item).new(GuestCans_Scene))
      expect(GuestCans_Scene.state).to be_nil
    end
  end
end
```
 * Run your specs: `bundle exec rspec`

Bonus, if you want to play in a sandbox to explore what's available (either for
specs or for writing rules) via a REPL, run `bundle console`, and inside of that
run `Bundler.require(:test)`. It will first load up the OpenHAB dependencies,
and then load rules in, then drop you into IRB.

### Spec Writing Tips

 * All items are reset to NULL before each spec.
 * `on_start` triggers are _not_ honored. Items will be reset to NULL before
   the next spec anyway, so just don't waste the energy running them. You
   can still trigger rules manually.
 * Rule triggers besides item related triggers (such as
   thing status, cron, or watchers) are not triggered. You can test them with
   `trigger_rule("rule name"[, event])`.
 * You can trigger channels directly with `trigger_channel(channel, data)`.
 * Timers aren't triggered automatically. Use the `execute_timers` helper to
   execute any timers that are ready to run. The `timecop` gem is
   automatiocally included, so use `Timecop.travel(5.seconds)` (for example)
   to travel forward in time and have timers ready to execute.
 * Logging levels can be changed in your code. Setting a log level for a logger
   further up the chain (separated by dots) applies to all loggers underneath
   it.
```ruby
OpenHAB::Log.logger("org.openhab.core.automation.internal.RuleEngineImpl").level = :debug
OpenHAB::Log.logger("org.openhab.core.automation").level = :debug
OpenHAB::Log.root.level = :debug
OpenHAB::Log.events.level = :info
```
 * Sometimes items are set to `autoupdate="false"` in production to ensure the
   devices responds, but you don't really care about the device in tests, you
   just want to check if the effects of a rule happened. You can enable
   autoupdating of all items by calling `autoupdate_all_items` from either
   your spec itself, or a `before` block.
 * Differing from when OpenHAB loads rules, all rules are loaded into a single
   JRuby execution context, so changes to globals in one file will affect other
   files.
 * Some actions may not be available; you should stub them out if you use them.
   Core actions like `notify`, `say`, and `play_sound` are stubbed to only log
   a message (at debug level).
 * You may want to avoid rules from firing while setting up the proper state for
   a test. In that case, use the `suspend_rules {}` helper.
 * Item persistence is enabled by default using an in-memory story that only
   tracks changes to items.

## Configuration

There are a few environment variables you can set to help the gem find the
necessary dependencies. The default should work for an OpenHABian install
or installation on Ubuntu or Debian with .debs. You may need to customize them
if your installation is laid out differently. Additional OpenHAB or Karaf
specific system properties will be set the same as OpenHAB would.

| Variable                 | Default                 | Description                                                         |
| ------------------------ | ----------------------- | ------------------------------------------------------------------- |
| `$OPENHAB_HOME`          | `/usr/share/openhab`    | Location for the OpenHAB installation                               |
| `$OPENHAB_RUNTIME`       | `$OPENHAB_HOME/runtime` | Location for OpenHAB's private Maven repository containing its JARs |

## Transformations

Ruby transformations _must_ have a magic comment `# -*- mode: ruby -*-` in them to be loaded.
Then they can be accessed as a method on `OpenHAB::Transform` based on the filename:

```
OpenHAB::Transform.compass("59 °")
OpenHAB::Transform.compass("30", param: "7")
OpenHAB::Transform::Ruby.compass("59 °")
```

They're loaded into a sub-JRuby engine, just like they run in OpenHAB.

## IRB

If you would like to use a REPL sandbox to play with your items,
you can run `bundle console`. You may want to create an `.irbrc`
with the following contents to automatically boot things up:

```ruby
# frozen_string_literal: true

require "rubygems"
require "bundler"

Bundler.require(:default, :development, :test)

launch_karaf
autorequires
set_up_autoupdates
load_rules
load_transforms
```
