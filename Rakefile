# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

load File.expand_path("lib/tasks/libhegel.rake", __dir__)

require "standard/rake"

desc "Run the test suite with coverage measurement enforced at 100%"
task :coverage do
  ENV["COVERAGE"] = "1"
  Rake::Task["test"].invoke
end

task default: %i[coverage standard]
