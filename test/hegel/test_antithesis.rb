# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

# Since libhegel 0.51.1, the engine does not record the choices of a run of
# one test case inside Antithesis (detected from ANTITHESIS_OUTPUT_DIR) when
# no database is set. Such a run is a long-running workload, and its record
# grew without bound. Its failure is then not shrunk or replayed, and the case
# is not stamped for capture, so the report has no drawn values and no
# reproduce blob. These tests follow test_antithesis.rs in hegel-rust. Each
# runs a script in a child process, because the engine reads the variable
# from the environment of the process.
class TestAntithesis < Minitest::Test
  SCRIPT = <<~RUBY
    require "hegel"
    Hegel.test(test_cases: 1) do |tc|
      warn "ran the single case"
      tc.draw_integer(0, 9)
      raise "the single case fails"
    end
  RUBY

  def test_a_single_test_case_in_antithesis_runs_once_and_reports_its_failure
    Dir.mktmpdir do |output_dir|
      output, status = run_script("ANTITHESIS_OUTPUT_DIR" => output_dir)

      refute_predicate status, :success?
      assert_equal 1, output.scan("ran the single case").size, output
      assert_includes output, "the single case fails (RuntimeError)"
      refute_includes output, "reproduce_failure"
    end
  end

  def test_a_single_test_case_outside_antithesis_is_replayed
    output, status = run_script("ANTITHESIS_OUTPUT_DIR" => nil)

    refute_predicate status, :success?
    assert_operator output.scan("ran the single case").size, :>, 1, output
    assert_includes output, "the single case fails (RuntimeError)"
    assert_includes output, "reproduce_failure"
  end

  private

  def run_script(env)
    Dir.mktmpdir do |script_dir|
      script = File.join(script_dir, "single_case.rb")
      File.write(script, SCRIPT)
      Open3.capture2e(env, RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), script)
    end
  end
end
