# frozen_string_literal: true

module Hegel
  # Wraps one libhegel test-case handle. This is the A3 slice of the engine's
  # draw surface: hegel_generate_integer and hegel_generate_boolean directly,
  # nothing built on top of them yet.
  #
  # This is not a throwaway API. The Generator class planned for a later task
  # (tc.draw(generator)) is built on these same two primitives, the way every
  # other Hegel binding layers its higher-level generators over a small
  # native draw surface.
  class TestCase
    # #name_for's fallback when a draw has no better name (see below).
    DEFAULT_DRAW_NAME = "draw"

    # +impl+ and +ctx+ are carried alongside +handle+ so each draw call can
    # reach the same LibHegel implementation and context the run loop opened,
    # without this class knowing anything about the native binding layer or
    # the Fake.
    #
    # +record+ defaults to false: recording is Hegel::Runner's decision, made
    # only for the one, already-shrunk replay that produces a failure report
    # (see #record_draw for why every other iteration skips it).
    def initialize(impl, ctx, handle, record: false)
      @impl = impl
      @ctx = ctx
      @handle = handle
      @record = record
      @draws = record ? [] : nil
    end

    # The (name, value) pairs recorded so far, or nil when this instance was
    # not built to record. Hegel::Runner reads this once, after the block
    # that owns this test case has run to completion or raised.
    attr_reader :draws

    # hegel_generate_integer: an integer in [min_value, max_value].
    def draw_integer(min_value, max_value, label: nil)
      value = @impl.generate_integer(@ctx, @handle, min_value, max_value)
      record_draw(label, value)
      value
    end

    # hegel_generate_boolean: true with probability +p+ (default 0.5).
    def draw_boolean(p = 0.5, label: nil)
      value = @impl.generate_boolean(@ctx, @handle, p, false, false)
      record_draw(label, value)
      value
    end

    private

    # Records (name, value) for the eventual failure report. A no-op unless
    # +record+ was true at #initialize: a run iterates the generation and
    # shrink phases far more than once (Hegel::Runner.drive's own comment
    # measured 1003 iterations for a 20-test-case run that always failed),
    # so recording -- and later #inspect-ing -- every draw there would
    # dominate a failing run's cost. Only the last, already-shrunk replay
    # pays for it.
    def record_draw(label, value)
      return unless @record

      @draws << [name_for(label), value]
    end

    # The single place a draw's name is decided, tried in this order: the
    # caller's own label:, then a generic fallback. A later task adds a
    # step here, between the two: recovering the name from the caller's own
    # source with Prism (see docs/adr/0005). Keeping the order in one method
    # means that task only has to add one line, not find every call site.
    def name_for(label)
      label || DEFAULT_DRAW_NAME
    end
  end
end
