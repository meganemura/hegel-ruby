# frozen_string_literal: true

require_relative "runner"

module Hegel
  # Where a Hegel.test call lives, in the four pieces
  # hegel_settings_set_test_location takes. Under Antithesis the engine
  # reports each run's verdict as the assertion
  # "<class_name>::<function> passes properties" at file:begin_line, so two
  # calls that share a class_name and a function share one assertion.
  TestLocation = Data.define(:file, :begin_line, :class_name, :function)

  class TestLocation
    # Matches the label prefix Ruby 3.4 puts on a frame inside a block, so
    # that the method underneath names the test.
    BLOCK_PREFIX = /\A(?:block(?: \(\d+ levels\))? in )+/

    # Matches "Class#method" and "Class.method". Greedy, so a namespaced
    # class keeps its "::" and a "#<Class:0x...>" label splits at its last
    # separator.
    METHOD_LABEL = /\A(.+)[#.]([^#.]+)\z/

    # The first of +locations+ that is the caller's own, by the same rule
    # Runner.origin_for uses to name a failure (see ADR 0012), so a wrapper in
    # this gem, a gem, or the standard library is not named as the test.
    # +locations+ is never empty, because the frame of Hegel.test's own caller
    # exists even at the top of a script.
    def self.from_locations(locations)
      location = locations.find { |candidate| !Runner.infrastructure?(candidate.path) } || locations.first
      path = location.absolute_path || location.path
      root = File.join(Dir.pwd, "")
      file = path.start_with?(root) ? path.delete_prefix(root) : path
      class_name, function = names(location.label, file, location.lineno)
      new(file: file, begin_line: location.lineno, class_name: class_name, function: function)
    end

    # [class_name, function] for a frame +label+. A frame with no enclosing
    # method (a script body, or an RSpec example, whose block sits at the top
    # of its file) has no name of its own, so it takes its file and line:
    # that keeps two examples in one file from sharing one assertion.
    def self.names(label, file, lineno)
      match = METHOD_LABEL.match(label.sub(BLOCK_PREFIX, ""))
      return match.captures if match

      [file.delete_suffix(".rb"), "line #{lineno}"]
    end
    private_class_method :names
  end
end
