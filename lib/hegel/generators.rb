# frozen_string_literal: true

require_relative "errors"
require_relative "generator"
require_relative "lib_hegel"

module Hegel
  # The five generators Hegel::Syntax::Methods exposes as bare, include-able
  # methods (see docs/adr/0004): booleans, integers, floats, text, and
  # arrays.
  #
  # Each class validates its own options at #do_draw time, not at
  # construction: hegel-rust's own contributor documentation states that
  # every invalid combination of builder values must be caught at draw
  # time, and that the resulting message is public API, asserted against
  # by tests as a stable substring. This binding follows the same rule so a
  # generator built once and drawn from many times fails the same way
  # hegel-rust's does.
  module Generators
    # Hegel::Syntax::Methods#booleans. A boolean, true with probability +p+.
    class BooleanGenerator < Generator
      def initialize(p:)
        super()
        @p = p
      end

      def do_draw(tc)
        raise Hegel::Error, "booleans: p must be between 0.0 and 1.0, got #{@p}" unless (0.0..1.0).cover?(@p)

        tc.generate_boolean(@p)
      end
    end

    # Hegel::Syntax::Methods#integers. An integer in [min_value, max_value],
    # defaulting to the full 64-bit range when either bound is omitted.
    class IntegerGenerator < Generator
      # hegel_generate_integer takes int64_t bounds; a bound outside this
      # range needs hegel_generate_integer_big instead, out of scope for
      # this milestone (see the task's own decision record).
      INT64_MIN = -(2**63)
      INT64_MAX = (2**63) - 1

      def initialize(min_value:, max_value:)
        super()
        @min_value = min_value
        @max_value = max_value
      end

      def do_draw(tc)
        min_value = @min_value || INT64_MIN
        max_value = @max_value || INT64_MAX
        raise Hegel::Error, "integers: max_value < min_value" if max_value < min_value
        unless min_value.between?(INT64_MIN, INT64_MAX) && max_value.between?(INT64_MIN, INT64_MAX)
          raise Hegel::Error, "integers: bounds outside the 64-bit range are not supported yet"
        end

        tc.generate_integer(min_value, max_value)
      end
    end

    # Hegel::Syntax::Methods#floats. A double in [min_value, max_value],
    # unbounded (the full finite range) by default. allow_nan and
    # allow_infinity both default to false here, unlike hegel-rust's
    # floats() (true when neither bound is set): this milestone exposes a
    # plain, always-off-by-default surface and leaves
    # smallest_nonzero_magnitude, and the allow_nan/allow_infinity/bounds
    # interaction hegel-rust validates, unexposed (see the task's own
    # decision record).
    class FloatGenerator < Generator
      # hegel_generate_float's width; Ruby has one Float type, the 64-bit
      # IEEE 754 double, so this is never anything else.
      WIDTH = 64

      def initialize(min_value:, max_value:, allow_nan:, allow_infinity:, exclude_min:, exclude_max:)
        super()
        @min_value = min_value
        @max_value = max_value
        @allow_nan = allow_nan
        @allow_infinity = allow_infinity
        @exclude_min = exclude_min
        @exclude_max = exclude_max
      end

      def do_draw(tc)
        min_value = @min_value || -Float::INFINITY
        max_value = @max_value || Float::INFINITY
        raise Hegel::Error, "floats: max_value < min_value" if max_value < min_value

        tc.generate_float(
          WIDTH, min_value, max_value,
          allow_nan: @allow_nan, allow_infinity: @allow_infinity,
          exclude_min: @exclude_min, exclude_max: @exclude_max,
          smallest_nonzero_magnitude: LibHegel::HEGEL_FLOAT64_SMALLEST_NONZERO_MAGNITUDE_UNRESTRICTED
        )
      end
    end

    # Hegel::Syntax::Methods#text. A Unicode string of [min_size, max_size]
    # characters, unbounded above by default.
    class TextGenerator < Generator
      def initialize(min_size:, max_size:, codec:, min_codepoint:, max_codepoint:)
        super()
        @min_size = min_size
        @max_size = max_size
        @codec = codec
        @min_codepoint = min_codepoint
        @max_codepoint = max_codepoint
      end

      def do_draw(tc)
        max_size = @max_size || LibHegel::HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED
        raise Hegel::Error, "text: max_size < min_size" if max_size < @min_size

        # A fresh generator handle every draw, freed before this method
        # returns via Hegel::TestCase#with_string_generator, rather than
        # cached on this generator instance: hegel_string_generator_free
        # takes the context, so the handle cannot outlive it, and this
        # generator object can be drawn from again in a later run against a
        # different context. Caching the handle here would free it under
        # the wrong run's context the second time. hegel-rust's own text()
        # can cache its handle in a OnceLock because Rust's Drop runs the
        # free at a fixed, known scope exit; Ruby has no equivalent
        # lifetime to hang a cache on, so this pays the alphabet-building
        # cost every draw instead.
        tc.with_string_generator(
          min_size: @min_size, max_size: max_size, codec: @codec,
          min_codepoint: @min_codepoint || 0, max_codepoint: @max_codepoint || 0xFFFFFFFF
        ) { |generator| tc.generate_string(generator) }
      end
    end

    # Hegel::Syntax::Methods#arrays. An Array of values from +elements+,
    # with [min_size, max_size] entries, unbounded above by default.
    class ArrayGenerator < Generator
      def initialize(elements, min_size:, max_size:)
        super()
        @elements = elements
        @min_size = min_size
        @max_size = max_size
      end

      def do_draw(tc)
        raise Hegel::Error, "arrays: min_size must not be negative" if @min_size.negative?

        max_size = @max_size || LibHegel::HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED
        raise Hegel::Error, "arrays: max_size < min_size" if max_size < @min_size

        # HEGEL_LABEL_LIST around the whole array, HEGEL_LABEL_LIST_ELEMENT
        # around each element (#draw_element below): the reference binding
        # (hegel-typescript's drawList) wraps both, and the shrinker needs
        # both to shrink a compound draw correctly -- a missing or
        # misplaced span here shows up as a larger-than-minimal
        # counterexample, not a test failure (see docs/adr/0006).
        tc.start_span(LibHegel::HEGEL_LABEL_LIST)
        begin
          draw_elements(tc, max_size)
        ensure
          tc.stop_span(discard: false)
        end
      end

      private

      def draw_elements(tc, max_size)
        collection = tc.new_collection(@min_size, max_size)
        begin
          result = []
          result << draw_element(tc) while tc.collection_more(collection)
          result
        ensure
          tc.collection_free(collection)
        end
      end

      def draw_element(tc)
        tc.start_span(LibHegel::HEGEL_LABEL_LIST_ELEMENT)
        @elements.do_draw(tc)
      ensure
        tc.stop_span(discard: false)
      end
    end

    # Hegel::Syntax::Methods#just. Always returns +value+, drawing nothing:
    # there is no choice for libhegel to make, so this opens no span (a
    # span exists to let the shrinker retry or isolate a draw, and there is
    # nothing here to retry or isolate).
    class JustGenerator < Generator
      def initialize(value)
        super()
        @value = value
      end

      def do_draw(_tc)
        @value
      end
    end

    # Hegel::Syntax::Methods#sampled_from. One element of +collection+,
    # picked by drawing an index in [0, collection.size - 1].
    class SampledFromGenerator < Generator
      def initialize(collection)
        super()
        @collection = collection
      end

      def do_draw(tc)
        raise Hegel::Error, "sampled_from: collection must not be empty" if @collection.empty?

        tc.start_span(LibHegel::HEGEL_LABEL_SAMPLED_FROM)
        begin
          index = tc.generate_integer(0, @collection.size - 1)
          @collection.to_a[index]
        ensure
          tc.stop_span(discard: false)
        end
      end
    end

    # Hegel::Syntax::Methods#one_of. Draws from one of +generators+, picked
    # by drawing an index in [0, generators.size - 1].
    class OneOfGenerator < Generator
      def initialize(generators)
        super()
        @generators = generators
      end

      def do_draw(tc)
        raise Hegel::Error, "one_of: at least one generator is required" if @generators.empty?

        tc.start_span(LibHegel::HEGEL_LABEL_ONE_OF)
        begin
          index = tc.generate_integer(0, @generators.size - 1)
          @generators[index].do_draw(tc)
        ensure
          tc.stop_span(discard: false)
        end
      end
    end

    # Hegel::Syntax::Methods#optional. Draws from +generator+ with
    # probability 0.5, nil otherwise. Does not expose a p: keyword: this
    # milestone leaves generate_boolean at its own default probability.
    class OptionalGenerator < Generator
      def initialize(generator)
        super()
        @generator = generator
      end

      def do_draw(tc)
        tc.start_span(LibHegel::HEGEL_LABEL_OPTIONAL)
        begin
          tc.generate_boolean ? @generator.do_draw(tc) : nil
        ensure
          tc.stop_span(discard: false)
        end
      end
    end

    # Hegel::Syntax::Methods#tuples. Draws each of +generators+ in order
    # into an Array (Ruby has no tuple type; see docs/adr/0004). The label
    # table assigns tuples a single span around the whole draw, unlike
    # arrays/sets/hashes: each position is a distinct generator already,
    # not repeated draws of one, so there is no per-element span to open.
    class TupleGenerator < Generator
      def initialize(generators)
        super()
        @generators = generators
      end

      def do_draw(tc)
        tc.start_span(LibHegel::HEGEL_LABEL_TUPLE)
        begin
          @generators.map { |generator| generator.do_draw(tc) }
        ensure
          tc.stop_span(discard: false)
        end
      end
    end

    # Hegel::Syntax::Methods#sets. A Set of values from +elements+, with
    # [min_size, max_size] entries, unbounded above by default.
    class SetGenerator < Generator
      def initialize(elements, min_size:, max_size:)
        super()
        @elements = elements
        @min_size = min_size
        @max_size = max_size
      end

      def do_draw(tc)
        raise Hegel::Error, "sets: min_size must not be negative" if @min_size.negative?

        max_size = @max_size || LibHegel::HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED
        raise Hegel::Error, "sets: max_size < min_size" if max_size < @min_size

        tc.start_span(LibHegel::HEGEL_LABEL_SET)
        begin
          draw_elements(tc, max_size)
        ensure
          tc.stop_span(discard: false)
        end
      end

      private

      # Set, unlike Array, cannot hold a duplicate: every #collection_more
      # loop iteration that draws a value already in +result+ calls
      # #collection_reject instead of adding it, so libhegel offers the
      # same slot another attempt rather than counting a discarded
      # duplicate toward min_size (see Hegel::TestCase#collection_reject).
      def draw_elements(tc, max_size)
        collection = tc.new_collection(@min_size, max_size)
        begin
          result = Set.new
          while tc.collection_more(collection)
            value = draw_element(tc)
            if result.include?(value)
              tc.collection_reject(collection)
            else
              result << value
            end
          end
          result
        ensure
          tc.collection_free(collection)
        end
      end

      def draw_element(tc)
        tc.start_span(LibHegel::HEGEL_LABEL_SET_ELEMENT)
        @elements.do_draw(tc)
      ensure
        tc.stop_span(discard: false)
      end
    end

    # Hegel::Syntax::Methods#hashes. A Hash from +keys+ drawing each key and
    # +values+ each value, with [min_size, max_size] entries, unbounded
    # above by default. Uniqueness is judged on the key alone, matching
    # Ruby's own Hash: a later draw with a key already present replaces
    # nothing, so it is rejected the same way SetGenerator rejects a
    # duplicate element.
    class HashGenerator < Generator
      def initialize(keys, values, min_size:, max_size:)
        super()
        @keys = keys
        @values = values
        @min_size = min_size
        @max_size = max_size
      end

      def do_draw(tc)
        raise Hegel::Error, "hashes: min_size must not be negative" if @min_size.negative?

        max_size = @max_size || LibHegel::HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED
        raise Hegel::Error, "hashes: max_size < min_size" if max_size < @min_size

        tc.start_span(LibHegel::HEGEL_LABEL_MAP)
        begin
          draw_entries(tc, max_size)
        ensure
          tc.stop_span(discard: false)
        end
      end

      private

      def draw_entries(tc, max_size)
        collection = tc.new_collection(@min_size, max_size)
        begin
          result = {}
          while tc.collection_more(collection)
            key, value = draw_entry(tc)
            if result.key?(key)
              tc.collection_reject(collection)
            else
              result[key] = value
            end
          end
          result
        ensure
          tc.collection_free(collection)
        end
      end

      # Draws the key and its value as one unit inside a single
      # HEGEL_LABEL_MAP_ENTRY span (the label table gives hashes one span
      # per entry, not one per key and a second per value), so the
      # shrinker can retry the whole pair together.
      def draw_entry(tc)
        tc.start_span(LibHegel::HEGEL_LABEL_MAP_ENTRY)
        [@keys.do_draw(tc), @values.do_draw(tc)]
      ensure
        tc.stop_span(discard: false)
      end
    end
  end
end
