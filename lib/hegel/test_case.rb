# frozen_string_literal: true

require_relative "draw_name"
require_relative "lib_hegel"

module Hegel
  # Wraps one libhegel test-case handle: the native draw surface
  # (#generate_integer, #start_span, #new_collection, and so on) every
  # Hegel::Generator#do_draw is built on, plus the two recording entry
  # points a caller (or #draw) reaches for -- #draw_integer/#draw_boolean
  # for the two primitive draws, #draw for a Hegel::Generator.
  #
  # The native methods below intentionally do not record: a Hegel::Generator
  # composing several of them (Hegel::Generators::ArrayGenerator drawing one
  # element per loop iteration, say) must produce exactly one report entry
  # for the whole compound value, not one per native call it happens to
  # make. Only #draw_integer, #draw_boolean, and #draw record, each exactly
  # once for its own single value.
  class TestCase
    # #name_for's fallback when a draw has no better name (see below).
    DEFAULT_DRAW_NAME = "draw"

    # Frames from #name_for's own caller_locations call up to the user's own
    # source line: #record_draw's call to #name_for (1), the public
    # draw_integer/draw_boolean/draw call to #record_draw (2), and the
    # user's own call to that public method (3). The same depth serves
    # #draw as it does #draw_integer/#draw_boolean: #draw calls
    # #record_draw only after Hegel::Generator#do_draw has already
    # returned, so a generator's own frames (and any native calls it made)
    # are off the stack by the time #record_draw runs, leaving the same
    # three frames between #name_for and the user's own call site either
    # way. Verified empirically (see test/hegel/test_runner.rb), not just
    # reasoned about: Ruby's caller_locations counts real stack frames, and
    # a wrong guess here would misname every drawn value, not just fail
    # loudly.
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
      value = generate_integer(min_value, max_value)
      record_draw(label, value)
      value
    end

    # hegel_generate_boolean: true with probability +p+ (default 0.5).
    def draw_boolean(p = 0.5, label: nil)
      value = generate_boolean(p)
      record_draw(label, value)
      value
    end

    # Draws +generator+ (a Hegel::Generator) and records the single value it
    # produced, however many native calls +generator+ made to produce it.
    # +label+ is threaded through to #record_draw the same way it is for
    # #draw_integer/#draw_boolean, wins over a recovered name the same way.
    def draw(generator, label: nil)
      value = generator.do_draw(self)
      record_draw(label, value)
      value
    end

    # hegel_generate_integer, without recording. Hegel::Generators::
    # IntegerGenerator's own primitive; #draw_integer is this plus
    # recording.
    def generate_integer(min_value, max_value)
      @impl.generate_integer(@ctx, @handle, min_value, max_value)
    end

    # hegel_generate_boolean, without recording. Hegel::Generators::
    # BooleanGenerator's own primitive; #draw_boolean is this plus
    # recording.
    def generate_boolean(p = 0.5)
      @impl.generate_boolean(@ctx, @handle, p, false, false)
    end

    # hegel_generate_float. Hegel::Generators::FloatGenerator's own
    # primitive.
    def generate_float(width, min_value, max_value, allow_nan:, allow_infinity:, exclude_min:, exclude_max:,
      smallest_nonzero_magnitude:)
      @impl.generate_float(@ctx, @handle, width, min_value, max_value, allow_nan, allow_infinity, exclude_min,
        exclude_max, smallest_nonzero_magnitude)
    end

    # hegel_start_span, labelled with one of the Hegel::LibHegel::
    # HEGEL_LABEL_* constants. Every compound Hegel::Generator (map, filter,
    # arrays) opens one of these around its own draw; see #stop_span.
    def start_span(label)
      @impl.start_span(@ctx, @handle, label)
    end

    # hegel_stop_span, closing the span #start_span most recently opened.
    # +discard+ true marks it rejected (a filter predicate that did not
    # hold), so libhegel retries from before the span opened.
    def stop_span(discard: false)
      @impl.stop_span(@ctx, @handle, discard)
    end

    # hegel_new_collection: Hegel::Generators::ArrayGenerator's own sizing
    # primitive, paired with #collection_more and #collection_free.
    def new_collection(min_size, max_size)
      @impl.new_collection(@ctx, @handle, min_size, max_size)
    end

    # hegel_collection_more: whether to draw another element into
    # +collection+.
    def collection_more(collection)
      @impl.collection_more(@ctx, @handle, collection)
    end

    # hegel_collection_free.
    def collection_free(collection)
      @impl.collection_free(@ctx, collection)
    end

    # Runs the block with a string generator handle scoped to this one
    # call, freeing it before returning. See Hegel::Generators::
    # TextGenerator for why this is built fresh per draw rather than cached
    # on the generator instance.
    def with_string_generator(**kwargs, &block)
      LibHegel.with_string_generator(@impl, @ctx, **kwargs, &block)
    end

    # hegel_generate_string against +generator+ (from #with_string_generator).
    def generate_string(generator)
      @impl.generate_string(@ctx, @handle, generator)
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
