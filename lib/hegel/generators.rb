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
      # range dispatches to hegel_generate_integer_big instead (see
      # #do_draw), so integers()'s own caller-facing surface does not
      # change depending on which native call ends up making the draw --
      # only the dispatch threshold these two constants mark.
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

        if min_value.between?(INT64_MIN, INT64_MAX) && max_value.between?(INT64_MIN, INT64_MAX)
          tc.generate_integer(min_value, max_value)
        else
          tc.generate_integer_big(min_value, max_value)
        end
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
        tc.with_text_generator(
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

    # Hegel::Syntax::Methods#characters. A String of exactly one character,
    # sharing TextGenerator's own alphabet options (codec, min_codepoint,
    # max_codepoint) by delegating to a TextGenerator built with min_size
    # and max_size both fixed at 1 -- the same alphabet-building logic,
    # just bounded to a single character instead of a run of them. Opens
    # no span of its own for the same reason TextGenerator does not: the
    # delegated #do_draw is the whole draw, not a composition of several.
    class CharactersGenerator < Generator
      def initialize(codec:, min_codepoint:, max_codepoint:)
        super()
        @text = TextGenerator.new(
          min_size: 1, max_size: 1, codec: codec,
          min_codepoint: min_codepoint, max_codepoint: max_codepoint
        )
      end

      def do_draw(tc)
        @text.do_draw(tc)
      end
    end

    # Hegel::Syntax::Methods#binary. A byte String of [min_size, max_size]
    # bytes, unbounded above by default.
    class BinaryGenerator < Generator
      def initialize(min_size:, max_size:)
        super()
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
    # alphabet is not exposed here: the header's third argument accepts a
    # text generator to constrain the wildcard/padding characters this
    # regex can produce, but wiring that surface up is out of scope for
    # this batch (see the task's own decision record); nil, the header's
    # documented "no particular alphabet" default, is passed in its place.
    class FromRegexGenerator < Generator
      def initialize(pattern, fullmatch:)
        super()
        @pattern = pattern
        @fullmatch = fullmatch
      end

      def do_draw(tc)
        unless @pattern.is_a?(String)
          raise Hegel::Error, "from_regex: pattern must be a String in Python re syntax, not a #{@pattern.class}"
        end

        tc.with_regex_generator(@pattern, fullmatch: @fullmatch) { |generator| tc.generate_string(generator) }
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
        super()
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
    # Spanned with HEGEL_LABEL_IP_ADDRESS around the whole draw, the same
    # way OptionalGenerator spans its own boolean-then-delegate draw
    # (see the HEGEL_LABEL_* table): when both families are enabled this
    # generator makes two native calls (the family choice, then the
    # address) to produce one value, and the span is what lets the
    # shrinker retry that pair together instead of the two calls
    # separately.
    class IpAddressesGenerator < Generator
      def initialize(v4:, v6:)
        super()
        @v4 = v4
        @v6 = v6
      end

      def do_draw(tc)
        raise Hegel::Error, "ip_addresses: v4 and v6 must not both be false" if !@v4 && !@v6

        tc.start_span(LibHegel::HEGEL_LABEL_IP_ADDRESS)
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
    # hex form (matching SecureRandom.uuid's own format; Ruby's stdlib has
    # no dedicated UUID type, and SecureRandom itself returns a String --
    # see the task's own decision record for why this returns a String
    # rather than adding a dependency for one). version: nil (the default)
    # draws uniform random bits except the nil UUID, per the header; an
    # explicit version forces the RFC 4122 version and variant nibbles.
    #
    # Opens no span: HEGEL_LABEL_UUID is a per-draw label the engine itself
    # emits inside hegel_generate_uuid, not something this binding opens --
    # the header's own comment on HEGEL_LABEL_INTEGER says the same of
    # hegel_generate_integer/_big ("Emitted internally, like every per-draw
    # label"). BooleanGenerator, IntegerGenerator, and FloatGenerator each
    # make exactly one native call to produce their own value the same way
    # uuids() does here, and each opens no span of its own for the same
    # reason. A span belongs only around a generator that composes more
    # than one native call into one draw (see IpAddressesGenerator, whose
    # family choice and address draw are two calls under one span).
    class UuidsGenerator < Generator
      def initialize(version:)
        super()
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
    # Opens no span: hegel_generate_date makes exactly one native call to
    # produce its own value, and the header's own comment on
    # HEGEL_LABEL_REGEX ("callers normally never open this span themselves.
    # Likewise for the other engine-side compound draws below") covers
    # HEGEL_LABEL_DATE too, since it sits below REGEX in that same list --
    # the same one-native-call, no-span-of-our-own reasoning UuidsGenerator's
    # own comment already gives for HEGEL_LABEL_UUID.
    class DatesGenerator < Generator
      MIN_DATE = Date.new(1, 1, 1)
      MAX_DATE = Date.new(9999, 12, 31)

      def initialize(min_value:, max_value:)
        super()
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
    # Opens no span, for the same reason DatesGenerator does not (one
    # native call, HEGEL_LABEL_TIME sits below HEGEL_LABEL_REGEX in the same
    # header list).
    class TimesGenerator < Generator
      MIDNIGHT = "00:00:00.000000"
      LAST_MICROSECOND = "23:59:59.999999"

      # Matches exactly what #do_draw's own format("%02d:%02d:%02d.%06d",
      # ...) produces, so parsing and formatting agree on the same shape.
      FORMAT = /\A(\d{2}):(\d{2}):(\d{2})\.(\d{6})\z/

      def initialize(min_value:, max_value:)
        super()
        @min_value = min_value
        @max_value = max_value
      end

      def do_draw(tc)
        min_parts = parse(@min_value || MIDNIGHT, "min_value")
        max_parts = parse(@max_value || LAST_MICROSECOND, "max_value")
        raise Hegel::Error, "times: max_value < min_value" if (max_parts <=> min_parts).negative?

        hour, minute, second, microsecond = tc.generate_time(min_parts, max_parts)
        format("%02d:%02d:%02d.%06d", hour, minute, second, microsecond)
      end

      private

      # +value+'s hour/minute/second/microsecond as an Array of Integers,
      # or raises if it is not a String matching FORMAT. This layer does
      # not range-check the parsed fields (an hour of 99, say): measured
      # against libhegel 0.32.5, hegel_generate_time already returns
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
    # Opens no span, for the same reason DatesGenerator does not (one
    # native call, HEGEL_LABEL_DATETIME sits below HEGEL_LABEL_REGEX in the
    # same header list).
    class DatetimesGenerator < Generator
      MIN_DATETIME = Time.utc(1, 1, 1, 0, 0, 0, 0)
      MAX_DATETIME = Time.utc(9999, 12, 31, 23, 59, 59, 999_999)

      def initialize(min_value:, max_value:)
        super()
        @min_value = min_value
        @max_value = max_value
      end

      def do_draw(tc)
        min_value = @min_value || MIN_DATETIME
        max_value = @max_value || MAX_DATETIME
        raise Hegel::Error, "datetimes: max_value < min_value" if max_value < min_value

        date, time = tc.generate_datetime(
          [min_value.year, min_value.month, min_value.day],
          [min_value.hour, min_value.min, min_value.sec, min_value.usec],
          [max_value.year, max_value.month, max_value.day],
          [max_value.hour, max_value.min, max_value.sec, max_value.usec]
        )
        Time.utc(*date, *time)
      end
    end
  end
end
