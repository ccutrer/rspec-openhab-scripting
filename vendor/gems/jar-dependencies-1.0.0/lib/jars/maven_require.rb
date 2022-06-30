# frozen_string_literal: true

module Jars
  class MavenRequireDSL
    attr_reader :requirements

    def initialize
      @requirements = []
    end

    def require(args)
      @requirements << args
    end

    def resolve_dependencies_list(deps_lst)
      mvn = Jars::MavenExec.new(self)
      require "jars/maven_exec"
      mvn.resolve_dependencies_list(deps_lst)
    end
  end
end

def maven_require(&block)
  require "jars/installer"
  require "tempfile"

  dsl = Jars::MavenRequireDSL.new
  dsl.instance_eval(&block)

  deps_lst = File.join(Dir.pwd, "deps.lst")
  attempts = 1

  dsl.resolve_dependencies_list(deps_lst) unless File.exist?(deps_lst)
  begin
    deps = Jars::Installer.load_from_maven(deps_lst)

    deps.each do |dep|
      require_jar(*dep.gav.split(":"))
    end
  rescue LoadError
    raise unless attempts == 1

    attempts += 1

    File.unlink(deps_lst)
    retry
  end
end
