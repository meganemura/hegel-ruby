# frozen_string_literal: true

require_relative "../generators"

module Hegel
  module Syntax
    # The generator-constructing methods a caller can include to call bare,
    # matching FactoryBot::Syntax::Methods's shape (see docs/adr/0004):
    #
    #   RSpec.configure { |config| config.include Hegel::Syntax::Methods }
    #
    # This is the one place any of these methods is defined.
    # Hegel::Generators.<name> reaches the same methods without an
    # include, via Hegel::Generators extending this module below.
    module Methods
      # A boolean, true with probability +p+.
      def booleans(p: 0.5)
        Generators::BooleanGenerator.new(p: p)
      end

      # An integer in [min_value, max_value], defaulting to the full
      # 64-bit range when either bound is omitted.
      def integers(min_value: nil, max_value: nil)
        Generators::IntegerGenerator.new(min_value: min_value, max_value: max_value)
      end

      # A double in [min_value, max_value]. allow_nan and allow_infinity
      # default to what the bounds imply: NaN when the caller passed
      # neither bound, an infinity when the caller left either side open.
      # allow_subnormal defaults to true whenever the bounds admit a
      # subnormal.
      def floats(min_value: nil, max_value: nil, allow_nan: nil, allow_infinity: nil, exclude_min: false,
        exclude_max: false, allow_subnormal: nil)
        Generators::FloatGenerator.new(
          min_value: min_value, max_value: max_value, allow_nan: allow_nan, allow_infinity: allow_infinity,
          exclude_min: exclude_min, exclude_max: exclude_max, allow_subnormal: allow_subnormal
        )
      end

      # A Unicode string of [min_size, max_size] characters. +alphabet+ is a
      # String of the permitted characters, or a #characters generator; it
      # cannot be combined with the options after it.
      def text(min_size: 0, max_size: nil, alphabet: nil, codec: nil, min_codepoint: nil, max_codepoint: nil,
        categories: nil, exclude_categories: nil, include_characters: nil, exclude_characters: nil)
        Generators::TextGenerator.new(
          min_size: min_size, max_size: max_size, alphabet: alphabet, codec: codec,
          min_codepoint: min_codepoint, max_codepoint: max_codepoint, categories: categories,
          exclude_categories: exclude_categories, include_characters: include_characters,
          exclude_characters: exclude_characters
        )
      end

      # An Array of values from +elements+, with [min_size, max_size]
      # entries. With unique: true, no two entries are equal.
      def arrays(elements, min_size: 0, max_size: nil, unique: false)
        Generators::ArrayGenerator.new(elements, min_size: min_size, max_size: max_size, unique: unique)
      end

      # Always +value+, drawing nothing.
      def just(value)
        Generators::JustGenerator.new(value)
      end

      # One element of +collection+, picked at random.
      def sampled_from(collection)
        Generators::SampledFromGenerator.new(collection)
      end

      # An Array holding every element of +elements+ (anything #sampled_from
      # accepts) in an order the engine picks, shrinking towards the
      # original one.
      def permutations(elements)
        Generators::PermutationsGenerator.new(elements)
      end

      # An Array holding [min_size, max_size] of the elements of +elements+,
      # in their original order. Duplicate elements count as distinct.
      def subsequences(elements, min_size: 0, max_size: nil)
        Generators::SubsequencesGenerator.new(elements, min_size: min_size, max_size: max_size)
      end

      # An Array of [min_size, max_size] elements of +elements+. With
      # +replacement+ (the default) each is drawn independently and the
      # size is unbounded unless +max_size+ bounds it. Without it, each
      # element is used at most once and the size is capped at the number
      # of elements; hegel-rust names the two modes with_replacement and
      # without_replacement.
      def samples(elements, min_size: 0, max_size: nil, replacement: true)
        Generators::SamplesGenerator.new(elements, min_size: min_size, max_size: max_size, replacement: replacement)
      end

      # A value drawn from one of +generators+, picked at random.
      def one_of(*generators)
        Generators::OneOfGenerator.new(generators)
      end

      # A value drawn from +generator+ half the time, nil the other half.
      def optional(generator)
        Generators::OptionalGenerator.new(generator)
      end

      # An Array holding one value drawn from each of +generators+, in
      # order (Ruby has no tuple type; see docs/adr/0004).
      def tuples(*generators)
        Generators::TupleGenerator.new(generators)
      end

      # A Set of values from +elements+, with [min_size, max_size] entries.
      def sets(elements, min_size: 0, max_size: nil)
        Generators::SetGenerator.new(elements, min_size: min_size, max_size: max_size)
      end

      # A Hash whose keys are drawn from +keys+ and values from +values+,
      # with [min_size, max_size] entries.
      def hashes(keys, values, min_size: 0, max_size: nil)
        Generators::HashGenerator.new(keys, values, min_size: min_size, max_size: max_size)
      end

      # A String of exactly one character, sharing #text's own alphabet
      # options.
      def characters(codec: nil, min_codepoint: nil, max_codepoint: nil, categories: nil, exclude_categories: nil,
        include_characters: nil, exclude_characters: nil)
        Generators::CharactersGenerator.new(
          codec: codec, min_codepoint: min_codepoint, max_codepoint: max_codepoint, categories: categories,
          exclude_categories: exclude_categories, include_characters: include_characters,
          exclude_characters: exclude_characters
        )
      end

      # A byte String of [min_size, max_size] bytes.
      def binary(min_size: 0, max_size: nil)
        Generators::BinaryGenerator.new(min_size: min_size, max_size: max_size)
      end

      # A String matching +pattern+ (Python `re` syntax, not Ruby's
      # Regexp syntax; see Generators::FromRegexGenerator). fullmatch
      # requires the whole string to match, not just contain a match.
      # +alphabet+ is a #characters generator limiting every character of the
      # string.
      def from_regex(pattern, fullmatch: false, alphabet: nil)
        Generators::FromRegexGenerator.new(pattern, fullmatch: fullmatch, alphabet: alphabet)
      end

      # An RFC 5321/5322 email address String.
      def emails
        Generators::EmailsGenerator.new
      end

      # An RFC 3986 http/https URL String.
      def urls
        Generators::UrlsGenerator.new
      end

      # A fully-qualified domain name String of at most +max_length+
      # characters.
      def domains(max_length: 255)
        Generators::DomainsGenerator.new(max_length: max_length)
      end

      # An IPAddr, v4 or v6 depending on +v4+/+v6+ (see
      # Generators::IpAddressesGenerator).
      def ip_addresses(v4: true, v6: true)
        Generators::IpAddressesGenerator.new(v4: v4, v6: v6)
      end

      # A UUID String in the standard 8-4-4-4-12 hex form. version: nil (the
      # default) draws uniform random bits except the nil UUID; an explicit
      # version forces the RFC 4122 version and variant nibbles (see
      # Generators::UuidsGenerator).
      def uuids(version: nil)
        Generators::UuidsGenerator.new(version: version)
      end

      # A proleptic Gregorian calendar Date in [min_value, max_value],
      # defaulting to year 1 through year 9999.
      def dates(min_value: nil, max_value: nil)
        Generators::DatesGenerator.new(min_value: min_value, max_value: max_value)
      end

      # A time of day String, "HH:MM:SS.ffffff", in [min_value, max_value]
      # (also "HH:MM:SS.ffffff" Strings), defaulting to the full day.
      def times(min_value: nil, max_value: nil)
        Generators::TimesGenerator.new(min_value: min_value, max_value: max_value)
      end

      # A naive (no timezone) Time in [min_value, max_value], defaulting to
      # year 1 through year 9999 (see Generators::DatetimesGenerator).
      def datetimes(min_value: nil, max_value: nil)
        Generators::DatetimesGenerator.new(min_value: min_value, max_value: max_value)
      end

      # A "YYYY-MM-DD" String, years 1 through 9999. Takes no options.
      def date_strings
        Generators::DateStringsGenerator.new
      end

      # An "HH:MM:SS" String, with ".fffffffff" appended when the
      # nanosecond is not zero. Takes no options.
      def time_strings
        Generators::TimeStringsGenerator.new
      end

      # A "YYYY-MM-DDTHH:MM:SS[.fffffffff]" String, years 1 through 9999.
      # Takes no options.
      def datetime_strings
        Generators::DatetimeStringsGenerator.new
      end

      # A duration as Integer nanoseconds in [min_value, max_value], up to
      # 2**64 - 1 (see Generators::DurationsGenerator and docs/adr/0030).
      def durations(min_value: 0, max_value: (2**64) - 1)
        Generators::DurationsGenerator.new(min_value: min_value, max_value: max_value)
      end

      # A value built from imperative code: +block+ receives a draw
      # surface and may call #draw on it any number of times to assemble
      # one value (see Generators::CompositeGenerator).
      def composite(&block)
        Generators::CompositeGenerator.new(&block)
      end

      # A forward reference to a generator whose definition is supplied
      # later via #set, enabling self-recursive and mutually recursive
      # generators (see Generators::DeferredGenerator).
      def deferred
        Generators::DeferredGenerator.new
      end
    end
  end

  module Generators
    extend Syntax::Methods
  end
end
