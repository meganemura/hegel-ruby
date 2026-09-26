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
#   reload, loads the whole mutated file by a relative path, which breaks
#   Hegel::Runner.origin_for and killed three mutants the suite does not
#   catch.
# MUTINEER_ARGS passes more flags, for example
# MUTINEER_ARGS="--since origin/main" to mutate only the lines changed since
# origin/main.
#
# `rake mutation` fails on a survivor that the baseline does not list
# (ADR 0018). `rake mutation:baseline` rewrites the baseline from a full run.
MUTATION_BASELINE = "test/mutation-baseline.json"

def run_mutineer(*extra)
  require "shellwords"
  tests = Dir["test/*.rb", "test/hegel/*.rb"].sort -
    %w[test/test_helper.rb test/hegel/test_conformance.rb]
  args = ["lib", "--strategy", "redefine", *tests.flat_map { |t| ["--test", t] }, *extra, *Shellwords.split(ENV.fetch("MUTINEER_ARGS", ""))]
  rubyopt = ["-Itest", ENV["RUBYOPT"]].compact.join(" ")
  # mutineer keeps its cache here, and refuses an --output path whose
  # directory does not exist yet.
  mkdir_p ".mutineer", verbose: false
  sh({"RUBYOPT" => rubyopt}, "bundle", "exec", "mutineer", "run", *args)
end

# mutineer writes its JSON report on one line, so a change to it reads as one
# changed line in a pull request. mutineer's --baseline reads only
# schema_version, summary.score, summary.scoped, and each survivor's id, so
# the committed file keeps those and writes one survivor per line, sorted.
# It leaves out line numbers: an edit above a survivor would move every
# line after it, and the id does not depend on the position. "change" holds
# the mutated line before and after, so a reviewer can read the survivor.
def write_mutation_baseline(report_path, baseline_path)
  require "json"
  report = JSON.parse(File.read(report_path))
  # mutineer refuses a --since run as a baseline, since it covers only the
  # changed lines.
  abort "#{report_path} comes from a --since run; rewrite the baseline from a full run" if report.dig("summary", "scoped")
  rows = report.fetch("survivors").map do |survivor|
    change = survivor.fetch("diff").lines.grep(/^[-+] /).map { |line| line.chomp.sub(/^([-+]) +/, '\1 ') }.join(" | ")
    {"id" => survivor.fetch("id"), "file" => survivor.fetch("file"), "subject" => survivor.fetch("subject"),
     "operator" => survivor.fetch("operator"), "change" => change}
  end
  rows.sort_by! { |row| row.values_at("file", "subject", "id") }
  text = +"{\n"
  text << %(  "schema_version": #{report.fetch("schema_version").to_json},\n)
  text << %(  "summary": #{report.fetch("summary").slice("score", "scoped").to_json},\n)
  text << %(  "survivors": [\n#{rows.map { |row| "    #{row.to_json}" }.join(",\n")}\n  ]\n}\n)
  # The baseline is committed to a public repository, so a path from this
  # machine must not reach it.
  leak = [Dir.pwd, Dir.home].find { |path| text.include?(path) }
  abort "#{baseline_path} would contain #{leak}; not written" if leak
  File.write(baseline_path, text)
end

desc "Run mutation testing over lib/, and fail on a survivor that #{MUTATION_BASELINE} does not list"
task :mutation do
  # --baseline also fails on a lower score. A mutant that times out on a slow
  # machine leaves the score and can lower it by a fraction of a point, and
  # it can never add a survivor. The epsilon absorbs that, and the survivor
  # ids stay the gate.
  run_mutineer("--baseline", MUTATION_BASELINE, "--baseline-epsilon", "1")
end

namespace :mutation do
  desc "Rewrite #{MUTATION_BASELINE} from a full mutation testing run over lib/"
  task :baseline do
    report = ".mutineer/baseline-run.json"
    run_mutineer("--format", "json", "--output", report)
    write_mutation_baseline(report, MUTATION_BASELINE)
  end
end
