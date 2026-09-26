# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

load File.expand_path("lib/tasks/libhegel.rake", __dir__)
load File.expand_path("lib/tasks/platform_gems.rake", __dir__)

require "standard/rake"

desc "Run the test suite with coverage measurement enforced at 100%"
task :coverage do
  ENV["COVERAGE"] = "1"
  Rake::Task["test"].invoke
end

task default: %i[coverage standard]

# Mutation testing with mutineer, over lib/. Four settings make the suite
# run under it; ADR 0016 records why:
# - RUBYOPT gets -Itest, since mutineer puts only lib/ on the load path and
#   every test file starts with `require "test_helper"`.
# - Each test file gets its own --test flag. The flag takes one file, and a
#   second path after it becomes a source to mutate.
# - test_conformance.rb stays out. Its capture_subprocess_io reopens
#   $stdout, and mutineer replaces $stdout with a StringIO, so the file fails
#   before any mutant runs.
# - --strategy redefine reloads only the mutated method. The default,
#   reload, loads the whole mutated file again, and that alone failed tests
#   for three mutants the suite does not catch.
# MUTINEER_ARGS passes more flags, for example
# MUTINEER_ARGS="--since origin/main --format json --output .mutineer/run.json".
desc "Run mutation testing over lib/ with mutineer"
task :mutation do
  require "shellwords"
  tests = Dir["test/*.rb", "test/hegel/*.rb"].sort -
    %w[test/test_helper.rb test/hegel/test_conformance.rb]
  args = ["lib", "--strategy", "redefine", *tests.flat_map { |t| ["--test", t] }, *Shellwords.split(ENV.fetch("MUTINEER_ARGS", ""))]
  rubyopt = ["-Itest", ENV["RUBYOPT"]].compact.join(" ")
  # mutineer keeps its cache here, and refuses an --output path whose
  # directory does not exist yet.
  mkdir_p ".mutineer", verbose: false
  sh({"RUBYOPT" => rubyopt}, "bundle", "exec", "mutineer", "run", *args)
end
