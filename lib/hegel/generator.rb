# frozen_string_literal: true

require_relative "errors"
require_relative "lib_hegel"

module Hegel
  # Base class for every value generator (Hegel::Generators.integers,
  # .booleans, .arrays, and so on) and the two combinators, #map and
  # #filter, that build a new generator out of an existing one. Mirrors
  # hegel-rust's Generator<T> trait: #do_draw is the one method a concrete
  # generator implements, and #map/#filter come for free from this class
  # rather than from each generator repeating them.
  class Generator
    # Draws one value using +tc+ (a Hegel::TestCase). Every concrete
    # generator implements this; the base class only exists to raise a
    # clear error for a subclass that forgot to.
    def do_draw(_tc)
      raise NotImplementedError, "#{self.class} must implement #do_draw"
    end

    # Returns a new Generator whose #do_draw runs +block+ on the value this
    # generator drew, spanned with HEGEL_LABEL_MAPPED so the shrinker
    # treats the source draw and the transform as one unit (see
    # hegel-rust's Mapped, src/generators/generators.rs).
    def map(&block)
      Mapped.new(self, block)
    end

    # Returns a new Generator whose #do_draw retries this generator until
    # +block+ returns true for the drawn value, or discards the test case
    # if it never does. See Filtered for the retry budget.
    def filter(&block)
      Filtered.new(self, block)
    end

    # Generator#map's result. A private implementation detail of #map, not
    # part of this library's public generator vocabulary (unlike the five
    # under Hegel::Generators), so it lives here rather than in
    # generators.rb.
    class Mapped < Generator
      def initialize(source, block)
        super()
        @source = source
        @block = block
      end

      def do_draw(tc)
        tc.start_span(LibHegel::HEGEL_LABEL_MAPPED)
        @block.call(@source.do_draw(tc))
      ensure
        # discard is always false here: a span is only ever marked
        # rejected to ask libhegel to retry it with different data (see
        # Filtered below), and #map has no such retry -- an exception from
        # +block+ or +source+ propagates past this method instead, and the
        # span still has to close on the way out.
        tc.stop_span(discard: false)
      end
    end

    # Generator#filter's result. Retries the source generator, each
    # attempt in its own span, up to MAX_ATTEMPTS times before discarding
    # the test case (Hegel::AssumeFailed) -- the same budget hegel-rust's
    # Filtered spends before calling assume(false)
    # (src/generators/generators.rs), ported here rather than reinvented so
    # a predicate that (almost) never holds fails the same way in both
    # bindings.
    #
    # A predicate that never holds does not loop forever: libhegel's own
    # health check aborts a run that discards too many test cases in a
    # row, which Hegel::Runner.finish surfaces as Hegel::Error, the same
    # path an engine-level failure takes for any other reason.
    class Filtered < Generator
      MAX_ATTEMPTS = 3

      def initialize(source, block)
        super()
        @source = source
        @block = block
      end

      def do_draw(tc)
        MAX_ATTEMPTS.times do
          accepted = false
          value = nil
          tc.start_span(LibHegel::HEGEL_LABEL_FILTER)
          begin
            value = @source.do_draw(tc)
            accepted = @block.call(value)
          ensure
            tc.stop_span(discard: !accepted)
          end
          return value if accepted
        end
        raise Hegel::AssumeFailed
      end
    end
  end
end
