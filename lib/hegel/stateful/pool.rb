# frozen_string_literal: true

require_relative "../generator"

module Hegel
  module Stateful
    # A pool of previously generated values, for a later stateful rule to
    # draw one back out. Build one from the running test case, inside the
    # machine's own constructor:
    #
    #   Hegel::Stateful::Pool.new(tc)
    #
    # #add records a value under a fresh variable id (hegel_pool_add); #size
    # and #empty? read the Ruby-side count directly. Drawing goes through the
    # two generators below, not through this class's own storage, so a
    # chosen id is drawn (and shrunk, and recorded in a failure report) the
    # same way any other value is: #values_reusable leaves the drawn value in
    # the pool, #values_consumed removes it. hegel-rust's own Pool<T>
    # (src/stateful.rs) keeps the same three-way split between the engine's
    # variable-id choice, this class's own id-to-value map, and the two
    # generators.
    #
    # A caller never frees a pool. docs/adr/0011 has the reason: #initialize
    # opens the native handle through Hegel::TestCase#new_pool, which records
    # it on +tc+ itself, and Hegel::Runner frees every pool a test case
    # recorded once that test case is done -- the same "the test case owns
    # what it opened" split this library already uses for a state-machine
    # handle.
    class Pool
      def initialize(tc)
        @tc = tc
        @pool = tc.new_pool
        @values = {}
      end

      # Number of values currently in the pool.
      def size
        @values.size
      end

      # True when no values are in the pool.
      def empty?
        @values.empty?
      end

      # Records +value+ under a fresh variable id from hegel_pool_add.
      # Returns self, Set#add's own contract -- hegel-rust's own Pool::add
      # returns nothing instead, since Rust has no builder-chaining idiom for
      # this method to match.
      def add(value)
        variable_id = @tc.pool_add(@pool)
        @values[variable_id] = value
        self
      end

      # A Hegel::Generator over this pool's values: drawing it leaves the
      # chosen value in place, so the same value can be drawn again.
      def values_reusable
        ValuesReusable.new(@pool, @values)
      end

      # A Hegel::Generator over this pool's values: drawing it removes the
      # chosen value, so it is never drawn again.
      def values_consumed
        ValuesConsumed.new(@pool, @values)
      end

      # Hegel::Generator returned by Pool#values_reusable. Left un-namespaced
      # under Hegel::Generators, the same way Hegel::Generator::Mapped and
      # ::Filtered are: reached only through Pool#values_reusable, not part
      # of this library's own public generator vocabulary.
      class ValuesReusable < Generator
        def initialize(pool, values)
          super()
          @pool = pool
          @values = values
        end

        # Does not check @values.empty? before drawing: hegel_pool_generate
        # already answers HEGEL_E_ASSUME for an empty pool, which
        # Hegel::LibHegel.check! already translates to Hegel::AssumeFailed --
        # the same translation every other assumption failure gets.
        # hegel-rust's own ValuesReusable checks again on its own side, with
        # a tc.assume call ahead of its own pool_generate call; doing that
        # here too would only give the empty case two paths to drift apart
        # from each other.
        def do_draw(tc)
          variable_id = tc.pool_generate(@pool, false)
          @values.fetch(variable_id)
        end
      end

      # Hegel::Generator returned by Pool#values_consumed. Same reasoning as
      # ValuesReusable above for staying un-namespaced and for not
      # pre-checking emptiness.
      class ValuesConsumed < Generator
        def initialize(pool, values)
          super()
          @pool = pool
          @values = values
        end

        def do_draw(tc)
          variable_id = tc.pool_generate(@pool, true)
          value = @values.fetch(variable_id)
          @values.delete(variable_id)
          value
        end
      end
    end
  end
end
