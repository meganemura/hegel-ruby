# 0038: Hand the engine a failure summary and detail

## Status

Accepted. Supersedes in part
[ADR 0019](0019-report-failures-from-the-cases-the-engine-stamps.md).

## Context

libhegel 0.52.0 moves the printing of a test case's output into the
engine. Three changes in its C ABI reach this gem:

1. `hegel_test_case_should_capture` is removed. Two calls replace it.
   `hegel_test_case_wants_output` says whether the engine will use what a
   case prints: every case of a verbose run, and each case the engine
   stamps for capture, quiet runs included.
   `hegel_test_case_wants_detail` says whether the engine will use a
   failure's full diagnostic: every case of a debug run, and the stamped
   cases of a normal or verbose run. A quiet run wants no detail.
2. `hegel_mark_complete` takes a `summary` and a `detail` after the
   `origin`. An INTERESTING case must give a summary of one line when the
   engine wants its output, and a detail when it wants its detail. Each
   string must be valid UTF-8. The engine rejects any other call with
   `HEGEL_E_INVALID_ARG` and completes nothing, so the run cannot go on.
3. A NULL output callback to `hegel_run_start` now means no destination.
   Before 0.52.0 it meant stderr, and ADR 0035 records that this gem
   passes NULL. The engine exports `hegel_output_stderr` for a caller that
   wants stderr.

The engine also adds `hegel_failure_output` and `hegel_failure_diagnostic`,
which give the failure report that the engine kept. This gem builds its
report in Ruby (ADR 0035), so it does not need them for this update.

Measured against libhegel 0.52.0 on linux-amd64 with Ruby 3.4.10, over 10
runs each of a property that fails when a drawn integer in 0..1_000_000 is
above 500_000, with the default 100 test cases: a quiet run gave the body
101 to 175 cases, of which 5 wanted output and none wanted detail; a
normal run gave 110 to 148 cases, of which 5 wanted output and 5 wanted
detail.

## Decision

The runner reads both flags when a case starts. `wants_output` takes the
place of the old stamp: the case records its draws and notes only when it
is true.

A failing case gives `hegel_mark_complete` a summary when `wants_output`
is true, and a detail when `wants_detail` is true. Neither is built
otherwise, because a backtrace costs more than a shrink probe should pay.

- The summary is the caller's own location (the frame ADR 0012 picks for
  the origin), the first line of the message, and the exception class in
  parentheses: `test/foo_test.rb:12: too big: 7 (RuntimeError)`. Ruby puts
  the class after the message when it prints an uncaught exception, so the
  summary does too. The header asks for the location first, as a compiler
  diagnostic gives it. A message of several lines is cut at its first line
  and followed by ` …`, as the header asks and as hegel-rust's
  `render_summary` does.
- The detail is `Exception#full_message(highlight: false, order: :top)`:
  what Ruby prints for the exception on its own, with its backtrace.
- Both strings are made valid UTF-8 before they go to the engine. A binary
  string is read as UTF-8. A string in another encoding is converted. A
  byte that is still invalid becomes U+FFFD.

`Hegel::LibHegel::Real` passes `hegel_output_stderr` as the output
callback of every run. This keeps engine output on stderr, as it was
before 0.52.0, and it is what hegel-rust's `frontends/rust/src/ffi.rs`
passes when no sink is given. A C function lives as long as the library,
so it outlives the run, which the header requires of the callback.

Reading the engine's failure report through `hegel_failure_output` was
refused for this update. The engine's document holds only what a frontend
prints into it, and this gem does not print draws into it (ADR 0035), so
the report would be empty.

## Consequences

A normal run prints the same as before. Measured on the property above
with `show_statistics: true`, the stderr of a normal run was the same
against 0.51.6 and against 0.52.0. A quiet run prints nothing to stderr;
`test/hegel/test_runner.rb` asserts this against 0.52.0.

A verbose run prints more. Measured against 0.52.0: after each failing
case, the engine prints the summary, and for a case that stopped early it
prints "Test case stopped: out of data". The header says that a debug
run also prints the detail. The draws and notes of a case still
do not show in the engine's verbose output, as before.

A verbose run records the draws of every case, not only of the stamped
cases, because the engine wants the output of every case. A verbose run
costs more for this reason. A run at any other verbosity does not change.

ADR 0019's rule for keeping a capture still holds. The header says that
each failure the engine reports is the last case of that origin it runs,
and that this case wants its output. A newer capture with recorded draws
replaces an older one, so the last one is the case the engine reports.
