# rspec-openhab-scripting

This gem allows you to write unit tests for your OpenHAB rules written in
JRuby. It loads up a limited actual OpenHAB runtime environment, and populates
it with _only_ the items from your running OpenHAB instance. Because it is
a limited environment, with no actual bindings or things, you may need to stub
out those actions in your tests. The autoupdate manager is running, so any
commands sent to items that aren't marked as `autoupdate="false"` will update
automatically.

## Usage

You must run tests on an actual OpenHAB instance running, with your items
populated, and JRuby 9.3 must be installed. Strictly speaking, the JAR files
that compose OpenHAB must be available locally, your rule files must be
available locally, and the item definitions are fetched via the REST API from
OpenHAB.

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
and then load your items and rules in, then drop you into IRB.

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
   it. The events logger (corresponding to what normally goes to events.log)
   defaults to WARN level, so that it will be silent.
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

There are several environment variables you can set to help the gem find the
necessary dependencies. The defaults should work for an OpenHABian install
or installation on Ubuntu or Debian with .debs. You may need to customize them
if your installation is laid out differently. Additionally, Thing configuration
information is only available if OPENHAB_TOKEN is set, so if your rules access
thing or channel information, you should set this. You can obtain it by
following the instructions at
https://www.openhab.org/docs/configuration/apitokens.html.

| Variable                 | Default                 | Description                                                         |
| ------------------------ | ----------------------- | ------------------------------------------------------------------- |
| `$OPENHAB_HOST`          | `localhost`             | Network hostname for where to connect to the REST API               |
| `$OPENHAB_HTTP_PORT`     | `8080`                  | Network port for where to connect to the (non-encrypted) REST API   |
| `$OPENHAB_HOME`          | `/usr/share/openhab`    | Location for the OpenHAB installation                               |
| `$OPENHAB_RUNTIME`       | `$OPENHAB_HOME/runtime` | Location for OpenHAB's private Maven repository containing its JARs |
| `$OPENHAB_CONF`          | `/etc/openhab`          | Location for userdata, such as rules and items                      |
| `$OPENHAB_TOKEN`         | N/A                     | Access Token for accessing OpenHAB Rest API                         |
| `$JARS_LOCAL_MAVEN_REPO` | `~/.m2/repository`      | Location to cache JARs                                              |

Not configurable:
 These correspond to the jrubyscripting bundle's default settings, but are not read from OpenHAB (yet?).
 * It's assumed that your ruby rules are located at `$OPENHAB_CONF/automation/jsr223/ruby/personal`.
 * It's assumed that your ruby library path is located at `$OPENHAB_CONF/automation/lib/ruby`.

## Troubleshooting

If you're getting errors about class not found for something for OpenHAB
packages, you may need to repair your Maven repositories. When the gem boots,
it will search out its dependencies from `$OPENHAB_RUNTIME`, and install them
into `~/.m2/repository`, then cache the dependencies into `deps.lst` locally.
You can try deleting the local Maven repository in your home directory, and
`deps.lst` and try again. If you're getting other errors, or it seems like
rules aren't firing or just not working, try turning up logging on everything
to make sure OpenHAB is working internally. It may be internal differences in
how OpenHAB operates between the version you're running and the version I
developed on.
