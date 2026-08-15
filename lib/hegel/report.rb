# frozen_string_literal: true

module Hegel
  # Turns a failing run's recorded entries into the text a caller sees on
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
    # phase's. +entries+ is the [:draw, name, value] / [:note, message] list
    # Hegel::TestCase recorded on the final replay that produced this
    # failure, in call order, still un-#inspect'd/un-#to_s'd (see
    # Hegel::TestCase#record_draw and #note for why). +blob+ is the string
    # Hegel.test(reproduce_failure:) accepts to replay this same failure.
    Failure = Struct.new(:test_cases, :discarded, :entries, :blob)

    module_function

    # Assigns each :draw entry its display name: the name it was recorded
    # under, suffixed with a 1-based, per-name counter only when that name
    # occurs more than once among the :draw entries (their own relative
    # order, unchanged). A single "n" stays "n"; two draws both named "draw"
    # (the fallback every unlabelled draw shares) become "draw_1" and
    # "draw_2", the same way hegel-rust's `__draw_named` disambiguates a
    # repeated `repeatable`. :note entries carry no name to disambiguate and
    # pass through unchanged, in the position they were recorded.
    def assign_names(entries)
      counts = entries.each_with_object(Hash.new(0)) do |entry, tally|
        tally[entry[1]] += 1 if entry[0] == :draw
      end
      seen = Hash.new(0)
      entries.map do |entry|
        next entry unless entry[0] == :draw

        _tag, name, value = entry
        if counts[name] > 1
          seen[name] += 1
          [:draw, "#{name}_#{seen[name]}", value]
        else
          entry
        end
      end
    end

    # Renders one failure's block: its "Falsified after" header, its
    # entries in call order (:draw #inspect'd, :note #to_s'd -- both here,
    # on report assembly, not when Hegel::TestCase recorded them), and how
    # to reproduce it. A :note shares the :draw lines' 2-space indent
    # deliberately: both belong to the same block, and a different indent
    # would read as a different kind of thing instead of the same
    # call-order list.
    def render_failure(failure)
      cases = "#{failure.test_cases} test #{(failure.test_cases == 1) ? "case" : "cases"}"
      lines = ["Falsified after #{cases} (#{failure.discarded} discarded):", ""]
      assign_names(failure.entries).each do |entry|
        if entry[0] == :draw
          _tag, name, value = entry
          lines << "  #{name} = #{value.inspect}"
        else
          _tag, message = entry
          lines << "  #{message}"
        end
      end
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
