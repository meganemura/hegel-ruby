# frozen_string_literal: true

require "prism"

module Hegel
  # Recovers a drawn value's variable name from the caller's own source (see
  # docs/adr/0005), so a failure report can print `n = 501` instead of
  # `draw = 501` when the caller never passed a label:. This module only
  # answers "what name does path:lineno assign a value to"; deciding
  # whether to call it, and what to fall back to when it answers nil, is
  # Hegel::TestCase#name_for's job, not this one's.
  module DrawName
    # Node types #for treats as "this line names a drawn value". An
    # explicit list, not every Prism::Node subclass whose name ends in
    # WriteNode, because a wrong guess here (e.g. matching a constant
    # assignment as if it named a draw) would misname a report entry -- the
    # one outcome this feature must never risk. Local and instance
    # variables both expose the assigned name the same way (a Symbol,
    # including the leading "@" for an ivar), so one code path reads both.
    ASSIGNMENT_NODE_TYPES = [Prism::LocalVariableWriteNode, Prism::InstanceVariableWriteNode].freeze

    module_function

    # The name +path+:+lineno+ assigns a drawn value to, or nil when that
    # cannot be answered confidently: +path+ cannot be read, Prism cannot
    # parse it, or the assignments covering +lineno+ do not single one out.
    # A wrong name would misdirect a reader of the failure report more than
    # a missing one would, so an ambiguous line returns nil rather than
    # guessing between candidates.
    #
    # Several assignments can cover one line by nesting rather than by
    # ambiguity. `error = assert_raises do ... n = tc.draw_integer(...) ...
    # end` puts the draw inside both, and a reader has no doubt which one
    # names it. So the innermost wins: an enclosing assignment is discarded
    # whenever another candidate sits inside it. Two assignments written
    # side by side on one line contain neither the other, nothing singles
    # one out, and the answer is nil.
    def for(path, lineno)
      program = parse(path)
      return nil unless program

      matches = assignment_nodes(program).select { |node| covers?(node.location, lineno) }
      innermost = matches.reject { |node| matches.any? { |other| encloses?(node, other) } }
      innermost.one? ? innermost.first.name.to_s : nil
    end

    # Drops every cached parse. #for's only state; a fresh process would
    # never need this, but a test process that calls #for many times over
    # the life of the suite does, both to isolate one test's fixture file
    # from another's and to prove #parse only reads a given path once (see
    # #parse).
    def reset_cache
      @cache = {}
    end

    # +path+'s parsed Prism::ProgramNode, or nil if it could not be read or
    # parsed. Cached either way, success or nil, because a single failure
    # report names every draw the final replay recorded against the same
    # one file, and nothing about that file changes between those lookups.
    def parse(path)
      cache.fetch(path) { cache[path] = read_and_parse(path) }
    end

    def cache
      @cache ||= {}
    end

    # Reads and parses +path+. Returns nil, not the ParseResult, for either
    # failure mode #for's caller cares about: +path+ raising SystemCallError
    # (a nonexistent path -- eval, "-e", irb, or a file removed since the
    # caller was compiled) and Prism reporting a syntax error (#success?
    # false) for a path that did exist.
    def read_and_parse(path)
      result = Prism.parse(File.read(path))
      result.success? ? result.value : nil
    rescue SystemCallError
      nil
    end

    # Every ASSIGNMENT_NODE_TYPES node under +node+, found by walking the
    # whole tree: a drawn value's assignment can be nested arbitrarily deep
    # (inside a block, a method body, a conditional), and this module has
    # no way to know which nesting level to expect it at.
    def assignment_nodes(node, matches = [])
      matches << node if ASSIGNMENT_NODE_TYPES.include?(node.class)
      node.compact_child_nodes.each { |child| assignment_nodes(child, matches) }
      matches
    end

    # Range containment, not a start-line match: Ruby's own caller_locations
    # reports the line a call's own last token is written on, and a
    # multi-line assignment's start line can differ from that -- e.g.
    # `n = tc\n  .draw_integer(...)` reports the second line, but the
    # assignment node's own start_line is the first.
    def covers?(location, lineno)
      (location.start_line..location.end_line).cover?(lineno)
    end

    # Whether +outer+ strictly contains +inner+, by byte offset rather than
    # by line: two assignments on one line share both line numbers, and only
    # the offsets tell them apart from a genuine nesting.
    def encloses?(outer, inner)
      return false if outer.equal?(inner)

      outer.location.start_offset <= inner.location.start_offset &&
        inner.location.end_offset <= outer.location.end_offset
    end
  end
end
