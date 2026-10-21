# frozen_string_literal: true

require "test_helper"
require "hegel/test_location"
require "support/fake_lib_hegel"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"

class TestTestLocation < Minitest::Test
  Frame = Struct.new(:path, :absolute_path, :lineno, :label)

  def test_a_hegel_test_call_records_its_own_file_line_class_and_method
    fake = Hegel::LibHegel::Fake.new
    line = __LINE__ + 1
    Hegel.test(impl: fake) { |_tc| }

    assert_equal [[relative_path_of_this_file, line, "TestTestLocation", __method__.to_s]],
      fake.settings_test_location_calls
  end

  def test_a_call_inside_a_block_names_the_method_that_holds_the_block
    fake = Hegel::LibHegel::Fake.new
    line = nil
    [1].each do
      [2].each do
        line = __LINE__ + 1
        Hegel.test(impl: fake) { |_tc| }
      end
    end

    assert_equal [[relative_path_of_this_file, line, "TestTestLocation", __method__.to_s]],
      fake.settings_test_location_calls
  end

  def test_a_replay_from_a_blob_records_the_location_too
    fake = Hegel::LibHegel::Fake.new
    line = __LINE__ + 2
    assert_raises(Hegel::Error) do
      Hegel.test(impl: fake, reproduce_failure: "blob") { |_tc| }
    end

    assert_equal [[relative_path_of_this_file, line, "TestTestLocation", __method__.to_s]],
      fake.settings_test_location_calls
  end

  def test_a_location_the_engine_rejects_raises_hegel_error
    fake = Hegel::LibHegel::Fake.new
    fake.settings_set_test_location_code = Hegel::LibHegel::HEGEL_E_INVALID_ARG

    assert_raises(Hegel::Error) { Hegel.test(impl: fake) { |_tc| } }
  end

  def test_an_instance_method_label_splits_into_class_and_method
    location = from("Foo::Bar#baz")

    assert_equal ["Foo::Bar", "baz"], [location.class_name, location.function]
  end

  def test_a_class_method_label_splits_into_class_and_method
    location = from("Foo.baz")

    assert_equal ["Foo", "baz"], [location.class_name, location.function]
  end

  def test_a_block_label_names_the_method_underneath
    assert_equal ["TestFoo", "test_bar"], names_of(from("block in TestFoo#test_bar"))
    assert_equal ["TestFoo", "test_bar"], names_of(from("block (3 levels) in TestFoo#test_bar"))
    assert_equal ["Foo", "bar"], names_of(from("block in block in Foo.bar"))
  end

  def test_a_top_level_label_names_the_file_and_line
    ["<main>", "<top (required)>", "block in <main>", "block (2 levels) in <top (required)>"].each do |label|
      assert_equal ["spec/foo_spec", "line 12"], names_of(from(label, path: in_cwd("spec/foo_spec.rb"), lineno: 12)), label
    end
  end

  def test_two_top_level_examples_in_one_file_get_distinct_names
    first = from("block (2 levels) in <top (required)>", lineno: 3)
    second = from("block (2 levels) in <top (required)>", lineno: 9)

    refute_equal names_of(first), names_of(second)
  end

  def test_a_label_without_a_class_names_the_file_and_line
    assert_equal ["lib/x", "line 4"], names_of(from("anonymous_method", path: in_cwd("lib/x.rb"), lineno: 4))
  end

  def test_a_path_under_the_working_directory_is_relative
    location = from("Foo#bar", path: in_cwd("test/a_test.rb"))

    assert_equal "test/a_test.rb", location.file
  end

  def test_a_path_outside_the_working_directory_stays_absolute
    location = from("Foo#bar", path: "/elsewhere/a_test.rb")

    assert_equal "/elsewhere/a_test.rb", location.file
  end

  def test_a_sibling_directory_sharing_the_working_directory_prefix_stays_absolute
    location = from("Foo#bar", path: "#{Dir.pwd}2/a_test.rb")

    assert_equal "#{Dir.pwd}2/a_test.rb", location.file
  end

  def test_a_frame_without_an_absolute_path_keeps_its_path
    location = Hegel::TestLocation.from_locations([Frame.new("-e", nil, 1, "<main>")])

    assert_equal ["-e", 1, "-e", "line 1"], location.to_h.values
  end

  def test_the_begin_line_is_the_frame_line
    assert_equal 41, from("Foo#bar", lineno: 41).begin_line
  end

  def test_frames_of_this_library_are_skipped
    inside = Frame.new(File.join(Hegel::Runner::LIBRARY_DIR, "hegel.rb"), nil, 99, "Hegel#wrapper")
    own = Frame.new(in_cwd("a_test.rb"), in_cwd("a_test.rb"), 5, "Foo#bar")

    assert_equal 5, Hegel::TestLocation.from_locations([inside, own]).begin_line
  end

  def test_the_first_frame_stands_in_when_every_frame_is_infrastructure
    inside = Frame.new(File.join(Hegel::Runner::LIBRARY_DIR, "hegel.rb"), nil, 99, "Hegel#wrapper")
    stdlib = Frame.new(File.join(Hegel::Runner::STDLIB_DIR, "set.rb"), nil, 7, "Set#each")

    assert_equal 99, Hegel::TestLocation.from_locations([inside, stdlib]).begin_line
  end

  def test_an_antithesis_run_writes_one_assertion_per_test_location
    # libhegel writes no sdk.jsonl on Windows; hegel-rust's own test_antithesis.rs is cfg(not(windows)).
    skip "the engine's Antithesis output is not written on Windows" if Gem.win_platform?

    Dir.mktmpdir do |output_dir|
      Dir.mktmpdir do |tmp_dir|
        script_dir = File.realpath(tmp_dir)
        script = File.join(script_dir, "probe.rb")
        File.write(script, <<~RUBY)
          require "hegel"
          class Probe
            def check
              Hegel.test(test_cases: 3, verbosity: :quiet) { |tc| tc.draw_integer(0, 9) }
            end
          end
          Probe.new.check
          Hegel.test(test_cases: 3, verbosity: :quiet) { |tc| tc.draw_integer(0, 9) }
        RUBY
        _, status = run_script(script, output_dir)

        assert_predicate status, :success?
        assertions = File.readlines(File.join(output_dir, "sdk.jsonl")).map { |line| JSON.parse(line).fetch("antithesis_assert") }
        evaluated = assertions.select { |assertion| assertion["hit"] }

        assert_equal ["Probe::check passes properties", "#{script_dir}/probe::line 8 passes properties"],
          evaluated.map { |assertion| assertion["message"] }
        assert_equal [true, true], evaluated.map { |assertion| assertion["condition"] }
        assert_equal [{"class" => "Probe", "function" => "check", "file" => script, "begin_line" => 4, "begin_column" => 0},
          {"class" => "#{script_dir}/probe", "function" => "line 8", "file" => script, "begin_line" => 8, "begin_column" => 0}],
          evaluated.map { |assertion| assertion["location"] }
      end
    end
  end

  private

  def relative_path_of_this_file
    Pathname.new(File.expand_path(__FILE__)).relative_path_from(Dir.pwd).to_s
  end

  def from(label, path: in_cwd("test/a_test.rb"), lineno: 1)
    Hegel::TestLocation.from_locations([Frame.new(path, path, lineno, label)])
  end

  def in_cwd(path)
    File.join(Dir.pwd, path)
  end

  def names_of(location)
    [location.class_name, location.function]
  end

  def run_script(script, output_dir)
    Open3.capture2e({"ANTITHESIS_OUTPUT_DIR" => output_dir}, RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), script)
  end
end
