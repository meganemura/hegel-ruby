# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

load File.expand_path("lib/tasks/libhegel.rake", __dir__)

require "standard/rake"

task default: %i[test standard]
