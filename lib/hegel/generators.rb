# frozen_string_literal: true

require "date"
require "ipaddr"
require_relative "errors"
require_relative "generator"
require_relative "lib_hegel"

module Hegel
  # The generators Hegel::Syntax::Methods exposes as bare, include-able
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
      # range dispatches to hegel_generate_integer_big instead (see
      # #do_draw), so integers()'s own caller-facing surface does not
      # change depending on which native call ends up making the draw --
      # only the dispatch threshold these two constants mark.
      INT64_MIN = -(2**63)
      INT64_MAX = (2**63) - 1

      def initialize(min_value:, max_value:)
        @min_value = min_value
        @max_value = max_value
      end

      def do_draw(tc)
        min_value = @min_value || INT64_MIN
        max_value = @max_value || INT64_MAX
        raise Hegel::Error, "integers: max_value < min_value" if max_value < min_value

        if min_value.between?(INT64_MIN, INT64_MAX) && max_value.between?(INT64_MIN, INT64_MAX)
          tc.generate_integer(min_value, max_value)
        else
          tc.generate_integer_big(min_value, max_value)
        end
      end
    end

    # Hegel::Syntax::Methods#floats. A double in [min_value, max_value],
    # unbounded by default.
    #
    # allow_nan and allow_infinity are three-valued: nil asks for the
    # default the bounds imply, and true or false overrides it. Three
    # implementations write that default as the same pair of expressions --
    # hegel-rust's src/generators/numeric.rs, hegel-go's primitives.go, and
    # hegel-typescript's src/generators/numeric.ts -- so an unbounded
    # floats() draws NaN and both infinities, and a fully bounded one draws
    # neither. docs/adr/0015 decides to follow that surface rather than the
    # always-off one this generator carried through 0.1.1.
    #
    # The two checks below come with those defaults: hegel-rust and
    # hegel-go each raise on the same two combinations, and the messages
    # here carry the substring theirs do.
    #
    # allow_subnormal is three-valued too. nil allows subnormals whenever
    # the bounds admit one, as hegel-rust's does, and the keyword maps to
    # hegel_generate_float's smallest_nonzero_magnitude: the smallest
    # subnormal when allowed, the smallest normal otherwise.
    class FloatGenerator < Generator
      # hegel_generate_float's width; Ruby has one Float type, the 64-bit
      # IEEE 754 double, so this is never anything else.
      WIDTH = 64

      def initialize(min_value:, max_value:, allow_nan:, allow_infinity:, exclude_min:, exclude_max:,
        allow_subnormal:)
        @min_value = min_value
        @max_value = max_value
        @allow_nan = allow_nan
        @allow_infinity = allow_infinity
        @exclude_min = exclude_min
        @exclude_max = exclude_max
        @allow_subnormal = allow_subnormal
      end

      def do_draw(tc)
        has_min = !@min_value.nil?
        has_max = !@max_value.nil?
        allow_nan = @allow_nan.nil? ? !has_min && !has_max : @allow_nan
        allow_infinity = @allow_infinity.nil? ? !has_min || !has_max : @allow_infinity

        if allow_nan && (has_min || has_max)
          raise Hegel::Error, "floats: cannot have allow_nan=true with min_value or max_value"
        end
        if allow_infinity && has_min && has_max
          raise Hegel::Error, "floats: cannot have allow_infinity=true with both min_value and max_value"
        end

        min_value = @min_value || -Float::INFINITY
        max_value = @max_value || Float::INFINITY
        raise Hegel::Error, "floats: max_value < min_value" if max_value < min_value

        tc.generate_float(
          WIDTH, min_value, max_value,
          allow_nan: allow_nan, allow_infinity: allow_infinity,
          exclude_min: @exclude_min, exclude_max: @exclude_max,
          smallest_nonzero_magnitude: smallest_nonzero_magnitude
        )
      end

      private

      def smallest_nonzero_magnitude
        allow_subnormal = @allow_subnormal.nil? ? subnormal_default : @allow_subnormal
        if allow_subnormal
          if !@min_value.nil? && @min_value >= Float::MIN
            raise Hegel::Error, "floats: InvalidArgument: allow_subnormal=true, but min_value excludes " \
              "all values below the smallest positive normal #{Float::MIN}"
          end
          if !@max_value.nil? && @max_value <= -Float::MIN
            raise Hegel::Error, "floats: InvalidArgument: allow_subnormal=true, but max_value excludes " \
              "all values above the smallest negative normal -#{Float::MIN}"
          end

          LibHegel::HEGEL_FLOAT64_SMALLEST_NONZERO_MAGNITUDE_UNRESTRICTED
        else
          if only_subnormals_between_bounds?
            raise Hegel::Error, "floats: InvalidArgument: allow_subnormal=false leaves no #{WIDTH}-bit " \
              "floating-point values in [#{@min_value}, #{@max_value}]"
          end

          Float::MIN
        end
      end

      def only_subnormals_between_bounds?
        return false if @min_value.nil? || @max_value.nil? || 0.0.between?(@min_value, @max_value)

        @max_value < Float::MIN && @min_value > -Float::MIN
      end

      def subnormal_default
        (@min_value.nil? || @min_value < Float::MIN) && (@max_value.nil? || @max_value > -Float::MIN)
      end
    end

    # The codecs hegel_string_generator_text accepts. Checked here as well so
    # the message matches hegel-rust's, which rejects an unknown codec before
    # the engine sees it.
    CODECS = %w[ascii latin-1 iso-8859-1 utf-8].freeze

    # The categories that contain surrogate codepoints. hegel-rust rejects
    # them in +categories+ because its strings cannot hold a surrogate.
    SURROGATE_CATEGORIES = %w[Cs C].freeze

    # Hegel::Syntax::Methods#characters. A String of exactly one character.
    # It also carries the alphabet options that TextGenerator and
    # FromRegexGenerator share, so all three build their text handle from the
    # same arguments.
    class CharactersGenerator < Generator
      def initialize(codec: nil, min_codepoint: nil, max_codepoint: nil, categories: nil, exclude_categories: nil,
        include_characters: nil, exclude_characters: nil)
        @options = {
          codec: codec, min_codepoint: min_codepoint, max_codepoint: max_codepoint, categories: categories,
          exclude_categories: exclude_categories, include_characters: include_characters,
          exclude_characters: exclude_characters
        }.freeze
      end

      def do_draw(tc)
        with_alphabet(tc, "characters", 1, 1) { |generator| tc.generate_string(generator) }
      end

      # Whether any alphabet option was passed, which TextGenerator needs to
      # refuse an +alphabet+ given beside one.
      def options_given?
        @options.each_value.any? { |value| !value.nil? }
      end

      # Yields a text handle over this alphabet for strings of
      # [min_size, max_size] characters, freed when the block returns.
      # +name+ is the factory method whose draw this is, for the messages.
      def with_alphabet(tc, name, min_size, max_size, &block)
        tc.with_text_generator(min_size: min_size, max_size: max_size, **engine_options(name), &block)
      end

      private

      def engine_options(name)
        codec = @options[:codec]
        raise Hegel::Error, "#{name}: invalid codec: #{codec}" if codec && !CODECS.include?(codec)

        categories = @options[:categories]
        exclude_categories = @options[:exclude_categories]
        if categories
          surrogate = categories.find { |category| SURROGATE_CATEGORIES.include?(category) }
          if surrogate
            raise Hegel::Error,
              "#{name}: Category \"#{surrogate}\" includes surrogate codepoints (Cs), " \
              "which a valid UTF-8 String cannot hold."
          end
          # hegel-rust drops exclude_categories when categories is given.
          exclude_categories = nil
        end
        @options.merge(categories: categories, exclude_categories: exclude_categories).compact
      end
    end

    # Hegel::Syntax::Methods#text. A Unicode string of [min_size, max_size]
    # characters, unbounded above by default. +alphabet+ is a String of the
    # permitted characters or a CharactersGenerator, and cannot be combined
    # with any of the character options.
    class TextGenerator < Generator
      def initialize(min_size:, max_size:, alphabet: nil, **character_options)
        @min_size = min_size
        @max_size = max_size
        @alphabet = alphabet
        @characters = CharactersGenerator.new(**character_options)
      end

      def do_draw(tc)
        alphabet = alphabet_generator
        max_size = @max_size || LibHegel::HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED
        raise Hegel::Error, "text: max_size < min_size" if max_size < @min_size

        # A fresh generator handle every draw, freed before this method
        # returns via Hegel::TestCase#with_text_generator, rather than
        # cached on this generator instance: hegel_string_generator_free
        # takes the context, so the handle cannot outlive it, and this
        # generator object can be drawn from again in a later run against a
        # different context. Caching the handle here would free it under
        # the wrong run's context the second time. hegel-rust's own text()
        # can cache its handle in a OnceLock because Rust's Drop runs the
        # free at a fixed, known scope exit; Ruby has no equivalent
        # lifetime to hang a cache on, so this pays the alphabet-building
        # cost every draw instead.
        alphabet.with_alphabet(tc, "text", @min_size, max_size) { |generator| tc.generate_string(generator) }
      end

      private

      def alphabet_generator
        return @characters if @alphabet.nil?

        raise Hegel::Error, "text: Cannot combine .alphabet() with character methods." if @characters.options_given?

        case @alphabet
        when String then CharactersGenerator.new(categories: [], include_characters: @alphabet)
        when CharactersGenerator then @alphabet
        else raise Hegel::Error, "text: alphabet must be a String or a characters generator, not a #{@alphabet.class}"
        end
      end
    end

    # Hegel::Syntax::Methods#arrays. An Array of values from +elements+,
    # with [min_size, max_size] entries, unbounded above by default. With
    # +unique+, an element equal to one already drawn is rejected through
    # #collection_reject, as SetGenerator does, so min_size still counts
    # distinct elements.
    class ArrayGenerator < Generator
      def initialize(elements, min_size:, max_size:, unique: false)
        @elements = elements
        @min_size = min_size
        @max_size = max_size
        @unique = unique
        @label = combined_label(@elements)
      end

      attr_reader :label

      def do_draw(tc)
        raise Hegel::Error, "arrays: min_size must not be negative" if @min_size.negative?

        max_size = @max_size || LibHegel::HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED
        raise Hegel::Error, "arrays: max_size < min_size" if max_size < @min_size

        # One span around the whole array, and one around each element
        # (#draw_element below) labelled with the element generator's own
        # label: the shrinker needs both to shrink a compound draw
        # correctly. A missing or misplaced span here shows up as a
        # larger-than-minimal counterexample, not a test failure (see
        # docs/adr/0006).
        tc.start_span(label)
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
          while tc.collection_more(collection)
            value = draw_element(tc)
            if @unique && result.include?(value)
              tc.collection_reject(collection, why: "duplicate element")
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
        tc.start_span(@elements.label)
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
        @collection = collection
      end

      def do_draw(tc)
        raise Hegel::Error, "sampled_from: collection must not be empty" if @collection.empty?

        tc.start_span(label)
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
        @generators = generators
        @label = combined_label(*@generators)
      end

      attr_reader :label

      def do_draw(tc)
        raise Hegel::Error, "one_of: at least one generator is required" if @generators.empty?

        tc.start_span(label)
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
        @generator = generator
        @label = combined_label(@generator)
      end

      attr_reader :label

      def do_draw(tc)
        tc.start_span(label)
        begin
          tc.generate_boolean ? @generator.do_draw(tc) : nil
        ensure
          tc.stop_span(discard: false)
        end
      end
    end

    # Hegel::Syntax::Methods#tuples. Draws each of +generators+ in order
    # into an Array (Ruby has no tuple type; see docs/adr/0004). One span
    # goes around the whole draw, unlike arrays/sets/hashes: each position
    # is a distinct generator already, not repeated draws of one, so there
    # is no per-element span to open.
    class TupleGenerator < Generator
      def initialize(generators)
        @generators = generators
        @label = combined_label(*@generators)
      end

      attr_reader :label

      def do_draw(tc)
        tc.start_span(label)
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
        @elements = elements
        @min_size = min_size
        @max_size = max_size
        @label = combined_label(@elements)
      end

      attr_reader :label

      def do_draw(tc)
        raise Hegel::Error, "sets: min_size must not be negative" if @min_size.negative?

        max_size = @max_size || LibHegel::HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED
        raise Hegel::Error, "sets: max_size < min_size" if max_size < @min_size

        tc.start_span(label)
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
        tc.start_span(@elements.label)
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
      ENTRY_LABEL = LibHegel.label_from_name("hegel-ruby.Hegel::Generators::HashGenerator.entry")

      def initialize(keys, values, min_size:, max_size:)
        @keys = keys
        @values = values
        @min_size = min_size
        @max_size = max_size
        @label = combined_label(@keys, @values)
        @entry_label = LibHegel.label_combine([ENTRY_LABEL, *[@keys, @values].map { |part| Generator.label_of(part) }])
      end

      attr_reader :label

      def do_draw(tc)
        raise Hegel::Error, "hashes: min_size must not be negative" if @min_size.negative?

        max_size = @max_size || LibHegel::HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED
        raise Hegel::Error, "hashes: max_size < min_size" if max_size < @min_size

        tc.start_span(label)
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

      # Draws the key and its value as one unit inside a single span, so the
      # shrinker can retry the whole pair together. The entry label combines
      # the key and value labels, as the hash's own label does.
      def draw_entry(tc)
        tc.start_span(@entry_label)
        [@keys.do_draw(tc), @values.do_draw(tc)]
      ensure
        tc.stop_span(discard: false)
      end
    end

    # What permutations, subsequences, and samples share: a draw of distinct
    # indices into the caller's sequence, and the span around the whole draw.
    module SequenceDrawing
      private

      # Raises for a size bound no draw can honour. The max_size check
      # reads as hegel-rust's does; the negative min_size check has no
      # hegel-rust counterpart, since a usize cannot be negative.
      def check_sizes(name, min_size, max_size)
        raise Hegel::Error, "#{name}: min_size must not be negative" if min_size.negative?
        raise Hegel::Error, "#{name}: Cannot have max_size < min_size" if max_size && max_size < min_size
      end

      def with_span(tc)
        tc.start_span(label)
        begin
          yield
        ensure
          tc.stop_span(discard: false)
        end
      end

      # Between +min_size+ and +max_size+ (nil, or anything above +size+,
      # means +size+) distinct indices below +size+, in draw order. Each draw is the index into what is still unchosen, not
      # into the whole sequence, so the shrinker's smallest value is the
      # earliest index not yet taken: the minimal sample is 0...min_size in
      # increasing order.
      def draw_index_sample(tc, size, min_size, max_size)
        remaining = (0...size).to_a
        chosen = []
        collection = tc.new_collection(min_size, [max_size || size, size].min)
        begin
          chosen << remaining.delete_at(tc.generate_integer(0, remaining.size - 1)) while !remaining.empty? && tc.collection_more(collection)
          chosen
        ensure
          tc.collection_free(collection)
        end
      end
    end

    # Hegel::Syntax::Methods#permutations. Every element of +elements+, in an
    # order the engine picks and shrinks towards the original one.
    class PermutationsGenerator < Generator
      include SequenceDrawing

      def initialize(elements)
        @elements = elements
      end

      def do_draw(tc)
        elements = @elements.to_a
        with_span(tc) do
          draw_index_sample(tc, elements.size, elements.size, elements.size).map { |index| elements[index] }
        end
      end
    end

    # Hegel::Syntax::Methods#subsequences. A subset of +elements+ with
    # [min_size, max_size] entries, in their original order. Duplicate
    # elements count as distinct.
    class SubsequencesGenerator < Generator
      include SequenceDrawing

      def initialize(elements, min_size:, max_size:)
        @elements = elements
        @min_size = min_size
        @max_size = max_size
      end

      def do_draw(tc)
        elements = @elements.to_a
        check_sizes("subsequences", @min_size, @max_size)
        if @min_size > elements.size
          raise Hegel::Error,
            "subsequences: Cannot generate a subsequence: min_size #{@min_size} is larger than " \
            "the #{elements.size} elements in the sequence"
        end

        with_span(tc) do
          indices = draw_index_sample(tc, elements.size, @min_size, @max_size)
          indices.sort.map { |index| elements[index] }
        end
      end
    end

    # Hegel::Syntax::Methods#samples. Between min_size and max_size elements
    # of +elements+, drawn with or without replacement. Without replacement
    # each element is used at most once, and duplicates in +elements+ count
    # as distinct. With replacement the size is unbounded unless max_size
    # bounds it.
    class SamplesGenerator < Generator
      include SequenceDrawing

      def initialize(elements, min_size:, max_size:, replacement:)
        @elements = elements
        @min_size = min_size
        @max_size = max_size
        @replacement = replacement
      end

      def do_draw(tc)
        elements = @elements.to_a
        check_sizes("samples", @min_size, @max_size)
        validate_for(elements.size)

        with_span(tc) do
          if @replacement
            draw_with_replacement(tc, elements)
          else
            indices = draw_index_sample(tc, elements.size, @min_size, @max_size)
            indices.map { |index| elements[index] }
          end
        end
      end

      private

      def validate_for(size)
        if @replacement
          if size.zero? && @min_size.positive?
            raise Hegel::Error, "samples: Cannot generate a non-empty sample from an empty sequence"
          end
        elsif @min_size > size
          raise Hegel::Error,
            "samples: Cannot generate a sample without replacement: min_size #{@min_size} is larger than " \
            "the #{size} elements in the sequence"
        end
      end

      def draw_with_replacement(tc, elements)
        max_size = elements.empty? ? 0 : @max_size || LibHegel::HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED
        collection = tc.new_collection(@min_size, max_size)
        begin
          result = []
          result << elements[tc.generate_integer(0, elements.size - 1)] while tc.collection_more(collection)
          result
        ensure
          tc.collection_free(collection)
        end
      end
    end

    # Hegel::Syntax::Methods#binary. A byte String of [min_size, max_size]
    # bytes, unbounded above by default.
    class BinaryGenerator < Generator
      def initialize(min_size:, max_size:)
        @min_size = min_size
        @max_size = max_size
      end

      def do_draw(tc)
        max_size = @max_size || LibHegel::HEGEL_COLLECTION_MAX_SIZE_UNBOUNDED
        raise Hegel::Error, "binary: max_size < min_size" if max_size < @min_size

        # hegel_generate_bytes already returns an Encoding::BINARY String
        # (see LibHegel::Real#generate_bytes); force_encoding here would
        # be redundant at best, and wrong the moment a caller's own bytes
        # happened to be valid UTF-8 and got silently relabelled as text.
        tc.generate_bytes(@min_size, max_size)
      end
    end

    # Hegel::Syntax::Methods#from_regex. A String matching +pattern+, which
    # the header documents as Python `re` syntax -- a different grammar
    # from Ruby's own Regexp, even though the two agree on simple patterns
    # (character classes, quantifiers, alternation). fullmatch defaults to
    # false, matching hegel_string_generator_regex's own documented
    # default: the drawn string only has to contain a match, not equal one.
    #
    # +pattern+ must be a String, checked at draw time like every other
    # validation in this file. A Ruby Regexp is rejected rather than
    # accepted and translated: Regexp#source drops modifiers such as /i,
    # /m, and /x silently, and the two grammars give the same characters
    # different meanings in places -- Ruby's ^ and $ are always line
    # anchors, where Python re's are string anchors unless re.MULTILINE is
    # set, and Ruby's [[:alpha:]] POSIX bracket syntax has no Python re
    # counterpart at all. Accepting a Regexp here would build a generator
    # whose output quietly stopped matching the flags or anchors its
    # caller wrote, with nothing to signal the mismatch. A caller who has
    # confirmed a pattern needs no flags and uses only syntax the two
    # grammars share can still pass `my_regexp.source` explicitly.
    #
    # +alphabet+ is a CharactersGenerator that constrains every character of
    # the drawn string, padding included. Its text handle is sized 0..0, so an
    # alphabet with no characters still builds: the engine then only rejects
    # a pattern that needs one.
    class FromRegexGenerator < Generator
      def initialize(pattern, fullmatch:, alphabet: nil)
        @pattern = pattern
        @fullmatch = fullmatch
        @alphabet = alphabet
      end

      def do_draw(tc)
        unless @pattern.is_a?(String)
          raise Hegel::Error, "from_regex: pattern must be a String in Python re syntax, not a #{@pattern.class}"
        end
        unless @alphabet.nil? || @alphabet.is_a?(CharactersGenerator)
          raise Hegel::Error, "from_regex: alphabet must be a characters generator, not a #{@alphabet.class}"
        end

        return draw_regex(tc, nil) if @alphabet.nil?

        # Built fresh each draw, like TextGenerator's handle, and freed after
        # the regex handle that was built from it.
        @alphabet.with_alphabet(tc, "from_regex", 0, 0) { |alphabet| draw_regex(tc, alphabet) }
      end

      private

      def draw_regex(tc, alphabet)
        tc.with_regex_generator(@pattern, fullmatch: @fullmatch, alphabet: alphabet) do |generator|
          tc.generate_string(generator)
        end
      end
    end

    # Hegel::Syntax::Methods#emails. An RFC 5321/5322 email address String.
    # hegel_string_generator_email takes no arguments, so there is nothing
    # to validate and nothing for #initialize to hold.
    class EmailsGenerator < Generator
      def do_draw(tc)
        tc.with_email_generator { |generator| tc.generate_string(generator) }
      end
    end

    # Hegel::Syntax::Methods#urls. An RFC 3986 http/https URL String.
    # hegel_string_generator_url takes no arguments, for the same reason
    # EmailsGenerator has no #initialize.
    class UrlsGenerator < Generator
      def do_draw(tc)
        tc.with_url_generator { |generator| tc.generate_string(generator) }
      end
    end

    # Hegel::Syntax::Methods#domains. A fully-qualified domain name String
    # of at most +max_length+ characters (default 255, the header's own
    # upper bound). The header documents the valid range as 4..=255; that
    # range is not checked here -- hegel_string_generator_domain already
    # returns HEGEL_E_INVALID_ARG outside it, which LibHegel.check! turns
    # into a Hegel::Error naming that code, so a local check here would
    # only repeat the engine's own validation with a worse message.
    class DomainsGenerator < Generator
      def initialize(max_length:)
        @max_length = max_length
      end

      def do_draw(tc)
        tc.with_domain_generator(max_length: @max_length) { |generator| tc.generate_string(generator) }
      end
    end

    # Hegel::Syntax::Methods#ip_addresses. An IPAddr, v4 or v6 depending on
    # +v4+/+v6+. Both true (the default) draws a boolean to pick the
    # family for each value; both false has no family left to draw from,
    # so it raises here rather than reaching hegel_generate_ipv4 or
    # hegel_generate_ipv6 at all.
    #
    # Spanned around the whole draw, the same way OptionalGenerator spans
    # its own boolean-then-delegate draw: when both families are enabled this
    # generator makes two native calls (the family choice, then the
    # address) to produce one value, and the span is what lets the
    # shrinker retry that pair together instead of the two calls
    # separately.
    class IpAddressesGenerator < Generator
      def initialize(v4:, v6:)
        @v4 = v4
        @v6 = v6
      end

      def do_draw(tc)
        raise Hegel::Error, "ip_addresses: v4 and v6 must not both be false" if !@v4 && !@v6

        tc.start_span(label)
        begin
          draw_address(tc)
        ensure
          tc.stop_span(discard: false)
        end
      end

      private

      # hegel_generate_ipv4/hegel_generate_ipv6 return the address's raw
      # network-order bytes (see TestCase#generate_ipv4/#generate_ipv6).
      # IPAddr.new_ntoh builds an IPAddr straight from that byte string,
      # picking v4 or v6 by its length (4 or 16), so no manual byte-to-
      # integer conversion belongs here.
      def draw_address(tc)
        use_v4 = (@v4 && @v6) ? tc.generate_boolean : @v4
        IPAddr.new_ntoh(use_v4 ? tc.generate_ipv4 : tc.generate_ipv6)
      end
    end

    # Hegel::Syntax::Methods#uuids. A UUID String in the standard 8-4-4-4-12
    # hex form, matching SecureRandom.uuid's own format. It returns a
    # String because Ruby's stdlib has no dedicated UUID type and
    # SecureRandom itself returns one; a richer type would mean a runtime
    # dependency, which this gem does not take for a formatting choice.
    # version: nil (the default)
    # draws uniform random bits except the nil UUID, per the header; an
    # explicit version forces the RFC 4122 version and variant nibbles.
    #
    # Opens no span: hegel_generate_uuid is one native call, and the engine
    # labels the spans around its own draws itself. BooleanGenerator,
    # IntegerGenerator, and FloatGenerator each make exactly one native call
    # the same way, and open no span of their own for the same reason. A
    # span belongs only around a generator that composes more than one
    # native call into one draw (see IpAddressesGenerator, whose family
    # choice and address draw are two calls under one span).
    class UuidsGenerator < Generator
      def initialize(version:)
        @version = version
      end

      def do_draw(tc)
        has_version = !@version.nil?
        raw = tc.generate_uuid(@version || 0, has_version)
        hex = raw.unpack1("H*")
        "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
      end
    end

    # Hegel::Syntax::Methods#dates. A proleptic Gregorian calendar Date in
    # [min_value, max_value], defaulting to the conventional full range
    # (year 1 through year 9999) when either bound is omitted -- hegel-rust's
    # own src/test_case.rs names this full_ranges::MIN_DATE/MAX_DATE, "what
    # Hypothesis's dates() spans".
    #
    # Opens no span, for the reason UuidsGenerator gives: one native call.
    class DatesGenerator < Generator
      MIN_DATE = Date.new(1, 1, 1)
      MAX_DATE = Date.new(9999, 12, 31)

      def initialize(min_value:, max_value:)
        @min_value = min_value
        @max_value = max_value
      end

      def do_draw(tc)
        min_value = @min_value || MIN_DATE
        max_value = @max_value || MAX_DATE
        raise Hegel::Error, "dates: max_value < min_value" if max_value < min_value

        year, month, day = tc.generate_date(
          [min_value.year, min_value.month, min_value.day], [max_value.year, max_value.month, max_value.day]
        )
        Date.new(year, month, day)
      end
    end

    # Since libhegel 0.36 the engine draws a time of day in whole
    # nanoseconds. times and datetimes keep microseconds, because hegel-rust,
    # hegel-cpp, and hegel-typescript do not agree on a finer precision. A
    # bound's microsecond widens to every nanosecond inside it, and the
    # drawn value rounds down, so every microsecond in range stays
    # reachable, both bounds included.
    def self.first_nanosecond(parts)
      hour, minute, second, microsecond = parts
      [hour, minute, second, microsecond * 1000]
    end

    def self.last_nanosecond(parts)
      hour, minute, second, microsecond = parts
      [hour, minute, second, (microsecond * 1000) + 999]
    end

    # Hegel::Syntax::Methods#times. A time of day String, "HH:MM:SS.ffffff",
    # in [min_value, max_value] (also "HH:MM:SS.ffffff" Strings), defaulting
    # to the conventional full day (00:00:00.000000 through 23:59:59.999999
    # -- hegel-rust's own full_ranges::MIDNIGHT/LAST_MICROSECOND) when either
    # bound is omitted.
    #
    # Returns a String, not a Time: Ruby's stdlib has no type for a bare
    # time of day (hour/minute/second/microsecond, with no date), and
    # building one from Time would attach an arbitrary date component to a
    # value that has none -- printing, comparing, or inspecting it would
    # read as though that date meant something, when it is only ever a
    # placeholder this generator invented to satisfy Time's own
    # constructor. min_value/max_value share that same String
    # representation, both for symmetry with the return value and because
    # it is the only representation available on the input side either.
    #
    # Opens no span, for the reason UuidsGenerator gives: one native call.
    class TimesGenerator < Generator
      MIDNIGHT = "00:00:00.000000"
      LAST_MICROSECOND = "23:59:59.999999"

      # Matches exactly what #do_draw's own format("%02d:%02d:%02d.%06d",
      # ...) produces, so parsing and formatting agree on the same shape.
      FORMAT = /\A(\d{2}):(\d{2}):(\d{2})\.(\d{6})\z/

      def initialize(min_value:, max_value:)
        @min_value = min_value
        @max_value = max_value
      end

      def do_draw(tc)
        min_parts = parse(@min_value || MIDNIGHT, "min_value")
        max_parts = parse(@max_value || LAST_MICROSECOND, "max_value")
        raise Hegel::Error, "times: max_value < min_value" if (max_parts <=> min_parts).negative?

        hour, minute, second, nanosecond = tc.generate_time(
          Generators.first_nanosecond(min_parts), Generators.last_nanosecond(max_parts)
        )
        format("%02d:%02d:%02d.%06d", hour, minute, second, nanosecond / 1000)
      end

      private

      # +value+'s hour/minute/second/microsecond as an Array of Integers,
      # or raises if it is not a String matching FORMAT. This layer does
      # not range-check the parsed fields (an hour of 99, say): measured
      # against libhegel 0.45.0, hegel_generate_time already returns
      # HEGEL_E_INVALID_ARG for an invalid time, translated by
      # LibHegel.check! once #do_draw calls tc.generate_time, the same
      # division of labor DomainsGenerator follows for its own
      # out-of-range max_length.
      def parse(value, name)
        match = value.is_a?(String) && FORMAT.match(value)
        raise Hegel::Error, "times: #{name} must be \"HH:MM:SS.ffffff\", got #{value.inspect}" unless match

        match.captures.map(&:to_i)
      end
    end

    # Hegel::Syntax::Methods#datetimes. A naive (no timezone) Time in
    # [min_value, max_value], defaulting to the conventional full range
    # (0001-01-01T00:00:00.000000 through 9999-12-31T23:59:59.999999 --
    # hegel-rust's own full_ranges::MIN_DATETIME/MAX_DATETIME) when either
    # bound is omitted.
    #
    # Built with Time.utc, not Time.new/Time.local: the drawn value has no
    # timezone of its own (hegel.h calls hegel_datetime_t "a date plus a
    # time of day, no timezone"), and UTC is the one zone every machine
    # running this gem's own tests agrees on, so a drawn value's own
    # year/month/day/hour/min/sec/usec read back exactly the fields that
    # were drawn, not shifted by whatever zone the process happens to run
    # in. min_value/max_value are read the same way: #do_draw takes
    # whatever zone the caller's own Time is already in at face value
    # (its own #year/#month/#day/#hour/#min/#sec/#usec), rather than
    # converting to UTC first, so a caller who wants a specific wall-clock
    # bound does not have to convert it themselves.
    #
    # Opens no span, for the reason UuidsGenerator gives: one native call.
    class DatetimesGenerator < Generator
      MIN_DATETIME = Time.utc(1, 1, 1, 0, 0, 0, 0)
      MAX_DATETIME = Time.utc(9999, 12, 31, 23, 59, 59, 999_999)

      def initialize(min_value:, max_value:)
        @min_value = min_value
        @max_value = max_value
      end

      def do_draw(tc)
        min_value = @min_value || MIN_DATETIME
        max_value = @max_value || MAX_DATETIME
        raise Hegel::Error, "datetimes: max_value < min_value" if max_value < min_value

        # A drawn value has whole microseconds, so a bound with a fraction of
        # one narrows to the whole microseconds inside the range. The lower
        # bound rounds up, in its own zone; the upper bound's #usec below
        # already drops its fraction.
        min_value = min_value.ceil(6)
        date, (hour, minute, second, nanosecond) = tc.generate_datetime(
          [min_value.year, min_value.month, min_value.day],
          Generators.first_nanosecond([min_value.hour, min_value.min, min_value.sec, min_value.usec]),
          [max_value.year, max_value.month, max_value.day],
          Generators.last_nanosecond([max_value.hour, max_value.min, max_value.sec, max_value.usec])
        )
        Time.utc(*date, hour, minute, second, nanosecond / 1000)
      end
    end

    # Formats a drawn [year, month, day] as hegel-rust's format_date does,
    # "YYYY-MM-DD" with the year zero-padded to four digits.
    def self.format_date(date)
      format("%04d-%02d-%02d", *date)
    end

    # Formats a drawn [hour, minute, second, nanosecond] as hegel-rust's
    # format_time does: nine fractional digits, present only when the
    # nanosecond is not zero.
    def self.format_time(time)
      hour, minute, second, nanosecond = time
      base = format("%02d:%02d:%02d", hour, minute, second)
      nanosecond.zero? ? base : format("%s.%09d", base, nanosecond)
    end

    # Hegel::Syntax::Methods#date_strings. A "YYYY-MM-DD" String over the
    # years 1 through 9999, the range hegel-rust passes. Takes no options,
    # as in hegel-rust.
    #
    # Opens no span, for the reason UuidsGenerator gives: one native call.
    class DateStringsGenerator < Generator
      def do_draw(tc)
        Generators.format_date(tc.generate_date([1, 1, 1], [9999, 12, 31]))
      end
    end

    # Hegel::Syntax::Methods#time_strings. An "HH:MM:SS" String over the
    # whole day, with ".fffffffff" appended when the drawn nanosecond is not
    # zero. Unlike #times, it keeps the engine's nanoseconds, as hegel-rust
    # does (see docs/adr/0022).
    #
    # Opens no span, for the reason UuidsGenerator gives: one native call.
    class TimeStringsGenerator < Generator
      def do_draw(tc)
        Generators.format_time(tc.generate_time([0, 0, 0, 0], [23, 59, 59, 999_999_999]))
      end
    end

    # Hegel::Syntax::Methods#datetime_strings. A "YYYY-MM-DDTHH:MM:SS" String
    # over years 1 through 9999, formatted as #date_strings and #time_strings
    # are.
    #
    # Opens no span, for the reason UuidsGenerator gives: one native call.
    class DatetimeStringsGenerator < Generator
      def do_draw(tc)
        date, time = tc.generate_datetime([1, 1, 1], [0, 0, 0, 0], [9999, 12, 31], [23, 59, 59, 999_999_999])
        "#{Generators.format_date(date)}T#{Generators.format_time(time)}"
      end
    end

    # Hegel::Syntax::Methods#durations. A span of time as whole nanoseconds
    # in [min_value, max_value], at most u64::MAX (about 584 years) as in
    # hegel-rust, whose generator is the model for the two messages below
    # (docs/adr/0030).
    class DurationsGenerator < Generator
      MAX_NANOSECONDS = (2**64) - 1

      def initialize(min_value:, max_value:)
        @min_value = min_value
        @max_value = max_value
      end

      def do_draw(tc)
        raise Hegel::Error, "durations: min_value must not be negative" if @min_value.negative?
        if @min_value > MAX_NANOSECONDS
          raise Hegel::Error, "durations: min_value exceeds the largest generatable Duration " \
            "(u64::MAX nanoseconds, about 584 years)"
        end

        # Saturates rather than raises, as hegel-rust's max_value does.
        max_value = [@max_value, MAX_NANOSECONDS].min
        raise Hegel::Error, "durations: Cannot have max_value < min_value" if max_value < @min_value

        IntegerGenerator.new(min_value: @min_value, max_value: max_value).do_draw(tc)
      end
    end

    # Hegel::Syntax::Methods#composite. Builds a generator from imperative
    # code, the way Hypothesis's @composite decorator and hegel-rust's
    # compose!/hegel-go's Composite let a caller assemble one value out of
    # several draws without writing a Generator subclass: +block+ receives
    # a draw surface (BlockTestCase below) and can call #draw on it any
    # number of times.
    #
    # One span goes around the block's draws. Its label names the block by
    # where it is written, so two different composites do not share a
    # label, the way hegel-rust's compose! labels each body by its source.
    class CompositeGenerator < Generator
      def initialize(&block)
        @block = block
        @label = LibHegel.label_combine(
          [self.class.label, LibHegel.label_from_name(Array(@block&.source_location).join(":"))]
        )
      end

      attr_reader :label

      def do_draw(tc)
        raise Hegel::Error, "composite: block is required" unless @block

        tc.start_span(label)
        begin
          @block.call(BlockTestCase.new(tc))
        ensure
          tc.stop_span(discard: false)
        end
      end

      # The draw surface a composite block receives. #draw reaches an
      # inner generator's own #do_draw directly -- the same non-recording
      # path ArrayGenerator#draw_element and every other compound
      # generator's do_draw already takes -- rather than the real
      # Hegel::TestCase#draw, which records. TestCase's own class comment
      # states the invariant this preserves: a compound generator making
      # several native calls produces exactly one report line for the
      # value it built, not one per call. A composite block draws exactly
      # the way a generator author's own do_draw does, so it is held to
      # the same rule; letting the block reach the recording #draw instead
      # would turn one composite draw into as many report lines as it made
      # nested draws.
      #
      # #draw_integer/#draw_boolean are defined here for the same reason,
      # not left to a method_missing delegation to the wrapped TestCase:
      # the real TestCase already exposes both as recording methods, and a
      # blanket delegation would let those two reach the engine
      # unrecorded-in-name only, still bypassing the single-report-line
      # rule #draw exists to keep the same way plain #draw would.
      class BlockTestCase
        def initialize(tc)
          @tc = tc
        end

        # Draws +generator+ without recording a report line of its own.
        def draw(generator)
          generator.do_draw(@tc)
        end

        # hegel_generate_integer, without recording (see #draw).
        def draw_integer(min_value, max_value)
          @tc.generate_integer(min_value, max_value)
        end

        # hegel_generate_boolean, without recording (see #draw).
        def draw_boolean(p = 0.5)
          @tc.generate_boolean(p)
        end
      end
    end

    # Hegel::Syntax::Methods#deferred. A forward reference to a generator
    # whose definition is not known yet, so a generator can refer to
    # itself (or to another deferred still being built) before #set
    # installs the real one -- enabling self-recursive and mutually
    # recursive generators, the same shape as hegel-rust's
    # DeferredGeneratorDefinition, hegel-cpp's DeferredGeneratorDefinition,
    # and hegel-java's Deferred:
    #
    #   tree = deferred
    #   tree.set(one_of(integers, arrays(tree)))
    #   tc.draw(tree)
    #
    # Opens no span: #do_draw makes no native call of its own, only
    # forwarding to whatever #set installed (one_of, above, already opens
    # its own span around that draw). This is the same
    # "a generator opens a span only around more than one native call it
    # makes itself" rule UuidsGenerator's own comment gives for a
    # generator that makes exactly one -- applied here to a generator that
    # makes zero. Every reference binding checked (hegel-rust's
    # DeferredGenerator, hegel-cpp's DeferredGenerator, hegel-java's
    # Deferred) opens none either.
    class DeferredGenerator < Generator
      def initialize
        @inner = nil
      end

      # Installs the generator this reference forwards to. May be called
      # only once: hegel-java's Deferred#set raises
      # IllegalStateException on a second call and hegel-cpp's throws;
      # hegel-rust's consumes self, making a second call a compile error.
      # Three independent bindings agree a second #set is a caller
      # mistake, not a silent overwrite or no-op, so this raises the same
      # way.
      def set(generator)
        raise Hegel::Error, "deferred: set called more than once" if @inner

        @inner = generator
      end

      # The installed generator's label, or this class's own before #set.
      # A generator built from this one before #set keeps the class label,
      # which is how a self-referential definition ends its own cycle, as
      # hegel-rust's DeferredGenerator does.
      def label
        @inner ? @inner.label : self.class.label
      end

      def do_draw(tc)
        raise Hegel::Error, "deferred: draw called before set" unless @inner

        @inner.do_draw(tc)
      end
    end
  end
end
