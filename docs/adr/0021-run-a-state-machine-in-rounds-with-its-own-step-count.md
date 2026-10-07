# 0021: Run a state machine in rounds, with its own step count

## Status

Accepted. Supersedes the `stateful_step_count:` keyword of `Hegel.test`.

## Context

Up to libhegel 0.32.5, a state machine had one call to pick the next rule,
and the step budget was a run setting,
`hegel_settings_set_stateful_step_count`, with an engine default of 50.
This binding exposed it as `Hegel.test(stateful_step_count:)`, and ran
every invariant after every rule that completed.

libhegel 0.33 to 0.43 changed the protocol. A machine runs in rounds:
`hegel_state_machine_next_group` starts each round, including the first,
and `hegel_state_machine_next_rule` takes a worker index. The step count
became an argument of `hegel_new_state_machine`, and the engine has no
default for it. Between rounds, `hegel_state_machine_should_check_invariant`
samples each invariant with probability 1 / step_count, so it runs about
once in a test case of full length; a flag at creation makes an invariant
run at every round instead. The caller runs every invariant on the initial
state and on the final state. The machine can also run concurrently, with
rule groups and weights.

hegel-rust (`Machine::steps`), hegel-go (`WithStatefulStepCount`), and
hegel-java (`Stateful.Options#stepCount`) put the step count on the
machine runner, with a default of 50. hegel-cpp keeps it in its settings.
hegel-go, hegel-cpp, and hegel-java sample invariants through the engine.
hegel-rust and hegel-java name the opt-out `always_run` and `alwaysRun`.

## Decision

`Hegel::Stateful.run(machine, tc, step_count: 50)` takes the step count,
and `Hegel.test` no longer takes `stateful_step_count:`. The keyword name
follows the engine's argument; 50 follows the three implementations that
moved it.

`invariant(name, always_run: true)` checks an invariant at every round.
Without it, the engine samples the invariant between rounds. Every
invariant runs before the first rule and after the last.

The machine is sequential: one group, equal weights, a concurrency of 1,
and worker index 0. This binding drives the engine from one thread, and a
concurrent machine needs one worker thread per drawn level of concurrency.
Rule weights stay out until a need for them shows up.

Keeping `stateful_step_count:` on `Hegel.test` was refused. It would carry
a value through the runner and the test case to a call that the stateful
module alone makes, and three of the four implementations that moved it put
it on the runner.

## Consequences

A caller who passed `stateful_step_count:` passes `step_count:` to
`Hegel::Stateful.run` instead. An invariant that a test relied on to run
after every rule needs `always_run: true`. A machine whose invariants are
sampled finds a broken invariant at the next sampled round, or at the
final check, which the shrinker then moves toward the step that broke it.
