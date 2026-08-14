# frozen_string_literal: true

module Hegel
  # Turns a failing run's recorded draws into the text a caller sees on
  # failure, and the blob Hegel.test(reproduce_failure:) accepts. Formatted
  # after hegel-rust's own failure report, so a reader moving between the
  # two bindings recognises the shape.
  #
  # This module only formats data it is handed; it does not know how a run
  # was driven, and does not write anywhere itself (see Hegel::Runner for
  # both).
  module Report
    # One failure's rendered ingredients. +test_cases+ and +discarded+ are
    # the generation phase's own counts up to that failure's first
    # appearance (see Hegel::Runner::GenerationStats), not the shrink
    # phase's. +draws+ is the (name, value) pairs Hegel::TestCase recorded
    # on the final replay that produced this failure, still un-#inspect'd
    # (see Hegel::TestCase#record_draw for why). +blob+ is the string
    # Hegel.test(reproduce_failure:) accepts to replay this same failure.
    Failure = Struct.new(:test_cases, :discarded, :draws, :blob)

    module_function

    # Assigns each draw its display name: the name it was recorded under,
    # suffixed with a 1-based, per-name counter only when that name occurs
    # more than once in +draws+ (Struct order is +draws+'s own draw order).
    # A single "n" stays "n"; two draws both named "draw" (the fallback
    # every unlabelled draw shares) become "draw_1" and "draw_2", the same
    # way hegel-rust's `__draw_named` disambiguates a repeated `repeatable`.
    def assign_names(draws)
      counts = draws.each_with_object(Hash.new(0)) { |(name, _value), tally| tally[name] += 1 }
      seen = Hash.new(0)
      draws.map do |name, value|
        if counts[name] > 1
          seen[name] += 1
          ["#{name}_#{seen[name]}", value]
        else
          [name, value]
        end
      end
    end

    # Renders one failure's block: its "Falsified after" header, its named
    # draws (#inspect'd here, on report assembly, not when Hegel::TestCase
    # recorded them), and how to reproduce it.
    def render_failure(failure)
      cases = "#{failure.test_cases} test #{(failure.test_cases == 1) ? "case" : "cases"}"
      lines = ["Falsified after #{cases} (#{failure.discarded} discarded):", ""]
      assign_names(failure.draws).each { |name, value| lines << "  #{name} = #{value.inspect}" }
      lines << ""
      lines << "To reproduce this failure, pass the blob below to Hegel.test:"
      lines << "    reproduce_failure: #{failure.blob.inspect}"
      lines.join("\n")
    end

    # Renders every failure, in the order given. A single failure is just
    # its own block. More than one gets hegel-rust's own distinct-failures
    # count first, with a blank line (the join separator) before every
    # block, including the first, matching the decided report shape.
    def render(failures)
      blocks = failures.map { |failure| render_failure(failure) }
      return blocks.first if blocks.size == 1

      (["Property-based test failed with #{blocks.size} distinct failures."] + blocks).join("\n\n")
    end
  end
end
