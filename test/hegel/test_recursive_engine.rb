# frozen_string_literal: true

require "test_helper"
require "support/conformance"

# recursive against the real engine, mirroring
# frontends/rust/tests/test_recursive.rs in hegeldev/hegel. Apart from
# test_recursive.rb, and left out of the mutation run (see the Rakefile),
# because the 30-leaf shrink alone takes about ten seconds, the time limit
# for one mutant, and the two exhausted-stream tests two seconds each; the
# Fake tests in test_recursive.rb pin every call the generator makes.
class TestRecursiveEngine < Minitest::Test
  include HegelDirectoryGuard
  include Hegel::Syntax::Methods
  include Hegel::Conformance

  Leaf = Data.define(:value)
  Branch = Data.define(:children)
  BinBranch = Data.define(:left, :right)

  INT32 = {min_value: -(2**31), max_value: (2**31) - 1}.freeze

  I64 = Hegel::Generators.integers(min_value: -(2**63), max_value: (2**63) - 1)

  # Draws i64 values, as the Rust test does, until the engine answers
  # StopTest, the way a body may. The generator is built once: the engine
  # allows about a million draws before it stops, and building one per
  # draw was a third of the time.
  def self.exhaust(tc)
    loop { tc.draw(I64) }
  rescue Hegel::StopTest
    nil
  end

  def teardown
    refute_new_hegel_directory
  end

  def test_recursive_draws_against_the_real_engine
    assert_simple_property(trees) { |tree| tree.is_a?(Leaf) || tree.is_a?(Branch) }
  end

  def test_max_depth_bounds_the_height
    assert_all_examples(trees(max_depth: 3)) { |tree| height(tree) <= 3 }
  end

  def test_max_leaves_bounds_the_leaf_count
    assert_all_examples(bin_trees(max_leaves: 4)) { |tree| leaf_count(tree) <= 4 }
  end

  def test_max_leaves_bounds_the_leaf_count_with_collection_branches
    assert_all_examples(trees(max_leaves: 5)) { |tree| leaf_count(tree) <= 5 }
  end

  # Most attempts at a leafless tree reject, which assert_simple_property
  # allows for.
  def test_zero_max_leaves_draws_leafless_values
    assert_simple_property(trees(max_leaves: 0)) { |tree| leaf_count(tree) == 0 }
  end

  def test_zero_max_leaves_with_unavoidable_leaves_rejects_every_case
    error = assert_raises(Hegel::Error) do
      Hegel.test(seed: 0, **QUIET_SETTINGS) { |tc| tc.draw(bin_trees(max_leaves: 0)) }
    end
    assert_includes error.message, "FilterTooMuch"
  end

  def test_a_leaf_that_always_rejects_rejects_every_case
    generator = recursive(just(:leaf).filter { false }) do |subtrees|
      tuples(subtrees, subtrees).map { |left, right| BinBranch.new(left, right) }
    end
    error = assert_raises(Hegel::Error) do
      Hegel.test(seed: 0, **QUIET_SETTINGS) { |tc| tc.draw(generator) }
    end
    assert_includes error.message, "FilterTooMuch"
  end

  def test_a_recursive_draw_on_an_exhausted_stream_overruns
    error = assert_raises(Hegel::Error) do
      Hegel.test(seed: 0, **QUIET_SETTINGS) do |tc|
        TestRecursiveEngine.exhaust(tc)
        tc.draw(trees)
        flunk "a recursive draw on an exhausted stream must overrun"
      end
    end
    assert_includes error.message, "LargeInitialTestCase"
  end

  # The leaf exhausts the stream and still returns a value, so completing
  # the draw has to surface the overrun.
  def test_completing_a_recursive_draw_on_an_exhausted_stream_overruns
    exhausting_leaf = Class.new(Hegel::Generator) do
      define_method(:do_draw) do |tc|
        TestRecursiveEngine.exhaust(tc)
        Leaf.new(0)
      end
    end.new
    generator = recursive(exhausting_leaf, max_depth: 0) do |subtrees|
      arrays(subtrees, max_size: 3).map { |children| Branch.new(children) }
    end

    error = assert_raises(Hegel::Error) do
      Hegel.test(seed: 0, **QUIET_SETTINGS) do |tc|
        tc.draw(generator)
        flunk "completing a recursive draw on an exhausted stream must overrun"
      end
    end
    assert_includes error.message, "LargeInitialTestCase"
  end

  def test_recursive_composes_inside_arrays
    assert_all_examples(arrays(trees(max_depth: 2), max_size: 3)) do |forest|
      forest.all? { |tree| height(tree) <= 2 }
    end
  end

  def test_recursive_draws_branches
    assert_kind_of Branch, find_any(trees) { |tree| tree.is_a?(Branch) }
  end

  def test_recursive_draws_nested_branches
    assert_operator height(find_any(trees) { |tree| height(tree) >= 2 }), :>=, 2
  end

  def test_shrinks_to_a_leaf
    assert_equal Leaf.new(0), minimal(trees) { true }
  end

  def test_the_minimal_branch_is_empty
    assert_equal Branch.new([]), minimal(trees) { |tree| tree.is_a?(Branch) }
  end

  def test_the_minimal_binary_branch_is_two_leaves
    assert_equal BinBranch.new(:leaf, :leaf), minimal(bin_trees) { |tree| tree.is_a?(BinBranch) }
  end

  def test_hoists_a_deep_witness_to_the_root
    tree = minimal(int_trees(max_depth: 3)) { |t| leaf_pair?(t) { |a, b| a & 1 == 1 && b & 1 == 1 } }
    assert_equal BinBranch.new(Leaf.new(1), Leaf.new(1)), tree
  end

  # Integer#remainder keeps the sign of the dividend, as Rust's % does.
  def test_hoists_a_rare_deep_witness_to_the_root
    tree = minimal(int_trees(max_depth: 4)) { |t| leaf_pair?(t) { |a, b| a.remainder(8) == 7 && b.remainder(8) == 7 } }
    assert_equal BinBranch.new(Leaf.new(7), Leaf.new(7)), tree
  end

  def test_shrinks_a_saturated_budget_to_an_exact_tree
    tree = minimal(bin_trees(max_leaves: 8)) { |t| leaf_count(t) >= 8 }
    assert_equal 8, leaf_count(tree)
    assert_equal 7, height(tree)
  end

  # The Rust test leaves the seed random. The shrink calls the body 15,000 to
  # 25,000 times whatever the seed, and seed 7 is among the cheapest of the 46
  # measured, so it pins the run near the low end.
  def test_draws_and_shrinks_large_trees
    assert_equal 30, leaf_count(minimal(trees, seed: 7) { |t| leaf_count(t) >= 30 })
  end

  def test_randomized_bounds_hold
    Hegel.test(**QUIET_SETTINGS) do |tc|
      max_depth = tc.draw(integers(min_value: 0, max_value: 5))
      max_leaves = tc.draw(integers(min_value: 1, max_value: 20))
      tree = tc.draw(bin_trees(max_depth: max_depth, max_leaves: max_leaves))
      assert_operator height(tree), :<=, max_depth
      assert_operator leaf_count(tree), :<=, max_leaves
    end
  end

  private

  def trees(**options)
    recursive(integers(**INT32).map { |n| Leaf.new(n) }, **options) do |subtrees|
      arrays(subtrees, max_size: 3).map { |children| Branch.new(children) }
    end
  end

  def bin_trees(**options)
    recursive(just(:leaf), **options) do |subtrees|
      tuples(subtrees, subtrees).map { |left, right| BinBranch.new(left, right) }
    end
  end

  def int_trees(**options)
    recursive(integers(**INT32).map { |n| Leaf.new(n) }, **options) do |subtrees|
      tuples(subtrees, subtrees).map { |left, right| BinBranch.new(left, right) }
    end
  end

  def height(tree)
    case tree
    when Branch then 1 + (tree.children.map { |child| height(child) }.max || 0)
    when BinBranch then 1 + [height(tree.left), height(tree.right)].max
    else 0
    end
  end

  def leaf_count(tree)
    case tree
    when Branch then tree.children.sum { |child| leaf_count(child) }
    when BinBranch then leaf_count(tree.left) + leaf_count(tree.right)
    else 1
    end
  end

  def leaf_pair?(tree, &pair)
    return false unless tree.is_a?(BinBranch)

    (tree.left.is_a?(Leaf) && tree.right.is_a?(Leaf) && pair.call(tree.left.value, tree.right.value)) ||
      leaf_pair?(tree.left, &pair) || leaf_pair?(tree.right, &pair)
  end

  # hegel-rust's assert_simple_property: 15 cases, with FilterTooMuch and
  # TooSlow suppressed.
  def assert_simple_property(generator)
    Hegel.test(test_cases: 15, suppress_health_check: [:filter_too_much, :too_slow], **QUIET_SETTINGS) do |tc|
      value = tc.draw(generator)
      assert yield(value), "predicate failed for: #{value.inspect}"
    end
  end
end
