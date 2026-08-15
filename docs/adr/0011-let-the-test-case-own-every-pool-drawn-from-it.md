# 0011: Let the test case own every pool drawn from it

## Status

Accepted. It builds on
[ADR 0010](0010-declare-stateful-rules-with-a-class-macro.md), which decided
how a state machine declares its rules.

## Context

A pool lets one rule act on a value an earlier rule produced. Without it, a
rule that frees a resource can only draw an arbitrary integer, and almost none
of those name a resource anything created. The engine tracks the pool as a set
of variable ids, chooses which id a draw returns, and shrinks that choice; the
caller keeps its own map from id to the value it generated.

`hegel_new_pool` hands back a handle that `hegel_pool_free` releases, and, like
every other free in this ABI, that call takes the context. So the context has
to outlive the pool. This project already answered the general form of that
question: release handles in an `ensure` in the code that owns the run, because
Ruby's garbage collector gives finalizer ordering no guarantee worth relying
on.

The difficulty is that a pool is created by the caller's own code, inside a
rule, and that code has no `ensure` wrapped around the run. Whoever writes
`Pool.new` is not in a position to free it.

hegel-ocaml, the other binding whose language collects garbage on its own
schedule, answers this by registering each pool on the test case that created
it and freeing them all when that case completes (`lib/internal.ml`,
`new_pool` and `free_owned_pools`). That is the same shape this library already
uses for the test-case handle itself.

## Decision

`Hegel::Stateful::Pool.new(tc)` creates a pool. The `Hegel::TestCase` records
every pool created from it, and `Hegel::Runner` frees them in the same `ensure`
that already frees the test-case handle, before that handle goes.

A finalizer backs nothing up here. The standing constraint allows one as a
backstop against a leak, but it must do nothing when the handle is already
free, and the three places that free a test case all run their `ensure` on
every path including a fatal exception. Adding a finalizer would add a second
owner for no case the first one misses.

A pool draws from the test case, so it must be built during one. The natural
place is the machine's own constructor, with the test case passed in from the
block that has it:

```ruby
Hegel.test { |tc| Hegel::Stateful.run(ResourceMachine.new(tc), tc) }
```

`Pool#add` records a value against a fresh variable id. Drawing goes through
two generators, not through the pool directly: `values_reusable` yields a
value and leaves it in the pool, `values_consumed` removes the value it
yields. Both are drawn with `tc.draw`, so the chosen value is named in the
failure report and its choice shrinks like any other draw. hegel-rust says
the same of its own two in `src/stateful.rs`, and this record follows
hegel-rust on meaning. hegel-ocaml reaches its own pool without a recorded
draw.

Drawing from an empty pool raises `Hegel::AssumeFailed`, translated from the
engine's own `HEGEL_E_ASSUME` by the existing result-code check. Inside a rule
that rejects the rule and the loop draws another, which is exactly what a rule
that frees a resource should do when nothing has been allocated yet.

## Consequences

A caller never frees a pool, and cannot leak one by forgetting to.

A caller also cannot outlive a pool past its test case on purpose. Holding one
in an instance variable and reusing it on the next case would reach a freed
handle; the machine is rebuilt per case for the same reason the model state is,
so the ordinary way of writing one does not run into this.

The engine records a pool draw as the chosen variable id rather than as an
index into the pool's current contents, so shrinking away an earlier `add`
never changes which variable a recorded choice refers to. The Ruby-side map
follows from that for free: an `add` that shrinks away never runs, so its id is
never in the map, and no draw can return it.
