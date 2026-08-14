# frozen_string_literal: true

require_relative "../generators"

module Hegel
  module Syntax
    # The generator-constructing methods a caller can include to call bare,
    # matching FactoryBot::Syntax::Methods's shape (see docs/adr/0004):
    #
    #   RSpec.configure { |config| config.include Hegel::Syntax::Methods }
    #
    # This is the one place any of these five methods is defined.
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
      # both default to false.
      def floats(min_value: nil, max_value: nil, allow_nan: false, allow_infinity: false, exclude_min: false,
        exclude_max: false)
        Generators::FloatGenerator.new(
          min_value: min_value, max_value: max_value, allow_nan: allow_nan, allow_infinity: allow_infinity,
          exclude_min: exclude_min, exclude_max: exclude_max
        )
      end

      # A Unicode string of [min_size, max_size] characters.
      def text(min_size: 0, max_size: nil, codec: nil, min_codepoint: nil, max_codepoint: nil)
        Generators::TextGenerator.new(
          min_size: min_size, max_size: max_size, codec: codec,
          min_codepoint: min_codepoint, max_codepoint: max_codepoint
        )
      end

      # An Array of values from +elements+, with [min_size, max_size]
      # entries.
      def arrays(elements, min_size: 0, max_size: nil)
        Generators::ArrayGenerator.new(elements, min_size: min_size, max_size: max_size)
      end

      # Always +value+, drawing nothing.
      def just(value)
        Generators::JustGenerator.new(value)
      end

      # One element of +collection+, picked at random.
      def sampled_from(collection)
        Generators::SampledFromGenerator.new(collection)
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
    end
  end

  module Generators
    extend Syntax::Methods
  end
end
