# frozen_string_literal: true

require_relative "draw_name"

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

    # Frames from #name_for's own caller_locations call up to the user's
    # own source line: #record_draw's call to #name_for (1), the public
    # draw_* method's call to #record_draw (2), and the user's own call to
    # that draw_* method (3). Named here, and passed into #name_for as an
    # argument, rather than folded into the caller_locations call inside
    # #name_for, because the planned Generator layer (tc.draw(generator))
    # adds one more frame between a public draw_* method and the user's own
    # call site, and that change should only have to update this one
    # number, not re-derive where caller_locations is called from.
    DRAW_CALLER_DEPTH = 3

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

      @draws << [name_for(label, DRAW_CALLER_DEPTH), value]
    end

    # The single place a draw's name is decided, tried in this order: the
    # caller's own label:, the name Hegel::DrawName recovers from the
    # caller's own source (see docs/adr/0005), then a generic fallback.
    # +depth+ is how many caller_locations frames separate this call from
    # the user's own source line (see DRAW_CALLER_DEPTH); +location+ is nil
    # only when the stack is shallower than +depth+, which no real draw_*
    # call site produces -- defensive, not a path this binding's own calls
    # reach.
    def name_for(label, depth)
      return label if label

      location = caller_locations(depth, 1)&.first
      (location && DrawName.for(location.path, location.lineno)) || DEFAULT_DRAW_NAME
    end
  end
end
