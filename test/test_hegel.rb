# frozen_string_literal: true

require "test_helper"

class TestHegel < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Hegel::VERSION
  end

  # Drives the gem-name entry point: `require "hegeltest"` must load the
  # library the same way `require "hegel"` does (lib/hegeltest.rb states why
  # both paths exist). A broken `require_relative` there fails this test,
  # and the require executes that file under coverage.
  def test_hegeltest_require_path_loads_the_hegel_namespace
    require "hegeltest"
    refute_nil ::Hegel::VERSION
  end
end
