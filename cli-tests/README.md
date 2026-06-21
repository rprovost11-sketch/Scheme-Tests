# cli-tests — process-boundary tests

Tests for the interpreters' **CLI and process-boundary** behavior:
command-line argument handling, exit codes, stdin piping, startup banner
suppression, and the `.run` report files a suite run writes to disk.

The runner (`cli-tests.scm`) is itself a Scheme program — **no shell**. It
relaunches its own interpreter with `(interpreter-argv)` + `(run-process …)`,
capturing each child's exit code and output directly. So it runs anywhere the
interpreter does (Windows / Linux / macOS), with nothing but the interpreter.

## Why this is its own category (a sister of `application-tests/`, not a child)

The placement follows the *subject* of the test — what is actually under
test — not the *mechanism* (how it happens to run):

- **`log-tests/`** (feature / compliance / regression) feed `>>> expr` to an
  already-launched, interactive interpreter and check `==> value`. Every test
  runs *inside* the process.
- **`application-tests/`** are Scheme **programs** — still in-language source,
  run *through* the interpreter, checking that primitives compose correctly in
  real programs. (The ecraven benchmarks live there: they are programs whose
  signal is correctness; the timing rig is just how that signal is collected.)
- **`cli-tests/`** (here) test the **outside of the process boundary** — argv
  parsing, exit status, the stdin pipe, files written to `runs/`. None of that
  is observable from a `>>> expr` line, which is why these cannot be `.log`
  tests, and are not Scheme programs either.

By contrast, a port's **white-box internals** (e.g. cppscheme2's `gc_test`,
compiled against its own GC headers, single-port) stay in that port's tree —
`scheme-tests/` is the shared, port-agnostic, black-box battery every port
must pass.

## Running

Through the registry (preferred — it sets the working directory so the fixture
resolves):

    ]suites cli-tests

Or directly, run from this directory so the relative fixture path resolves:

    <interp> cli-tests.scm        # exits non-zero if any check fails

The two ports differ only in the program-name prefix of error/usage text
(`pyscheme:` vs `cppscheme2:`) and the `.run` filename suffix
(`PyScheme.run` vs `CPPScheme2.run`); the harness asserts on the shared
message content and exit codes, never on those.

The `.run`-report checks use a **committed** fixture tests-root, `runfix/` (one
all-passing feature file, one with a deliberate failure, one all-passing
regression file — no temp dir, since R7RS has no `mkdir`). The runner drives a
listener session that points `]scheme-tests` at it, runs `]suites feature
regression`, and reads back the combined report whose path the listener prints
as `Test output: …`. The `runs/*.run` it writes there are git-ignored.

The whole run is deliberately cheap — a handful of process launches plus one
tiny fixture suite, well under a second per port — so it belongs in the
run-on-every-change bucket, not an occasional one.
