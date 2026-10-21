# frozen_string_literal: true

module Hegel
  # The grammars compiled during one run, keyed by everything the
  # compilation read. Hegel::Runner.run owns one and frees it after the run
  # and before the context; see docs/adr/0033.
  class GrammarCache
    # A compiled grammar handle and the marker standing for each explicit
    # terminal, in the order the terminals were named.
    Compiled = Data.define(:grammar, :markers)

    def initialize
      @entries = {}
    end

    # The entry under +key+, or the block's value, stored only once the
    # block returns, so a compilation that raises leaves nothing behind.
    def fetch(key)
      @entries.fetch(key) { @entries[key] = yield }
    end

    # Frees every grammar, carrying on past a free that raises so that the
    # rest are still freed before the context, and raises the first error
    # once all have been tried.
    def free_all(impl, ctx)
      error = nil
      @entries.each_value do |compiled|
        impl.grammar_free(ctx, compiled.grammar)
      rescue => e
        error ||= e
      end
      @entries.clear
      raise error if error
    end
  end
end
