# cli-tests — process-boundary tests

Shell-level tests for the interpreters' **CLI and process-boundary**
behavior: command-line argument handling, exit codes, stdin piping, startup
banner suppression, and the `.run` report files a suite run writes to disk.

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

`run.sh` takes the interpreter invocation as its single argument (passed
verbatim, so it may contain spaces) and runs the same contract against it.
Exits non-zero if any check fails.

    # pyScheme (run from its package dir so `python -m pyscheme` resolves)
    (cd ../../../3PyScheme && bash ../scheme-tests/cli-tests/run.sh "python -m pyscheme")

    # cppscheme2
    bash run.sh "/d/SWDEV/Languages/Lisp/4CPPScheme2/build/Release/cppscheme2.exe"

The two ports differ only in the program-name prefix of error/usage text
(`pyscheme:` vs `cppscheme2:`); the harness asserts on the shared message
content and exit codes, never the program name.
