# Testing catalog

Every test in the arsenal, and exactly how to run it. The goal is **parity**:
either party can run *all* the tests, so neither has a test the other can't run.

Paths below are relative to the `Lisp/` parent directory (the repos sit as
siblings: `scheme-tests/`, `3PyScheme/`, `4CPPScheme2/`). pyScheme is stdlib-only;
cppScheme2 tests need a Release build (`build/Release/cppscheme2.exe`).

## Run everything at once

```sh
bash scheme-tests/run-all-tests.sh          # fast+core arsenal (~2-3 min)
bash scheme-tests/run-all-tests.sh --slow   # + the ecraven correctness sweep (long)
```
Prints one pass/fail summary. **Known-open bugs are reported as `xfail`** (expected
to fail until fixed) and do not fail the run; an unexpected failure exits nonzero;
a known-open test that suddenly passes is flagged `FIXED!` (promote it).

## The individual tests

| Test | What it checks | How to run it |
|---|---|---|
| **Gated battery** (feature + compliance + regression, ~11.9k cases) | R7RS conformance + features + regression tripwires, in-process | In the REPL or Cherry: `]suites all` (or `]feature` / `]compliance` / `]regression`) |
| One `.log` file | a single suite file | `]feature test031-ports.log` (etc.) |
| **CLI / process-boundary** (15 checks) | argv, exit codes, stdin, `.run` reports | `bash scheme-tests/cli-tests/run.sh "<interp>"` — py needs `PYTHONPATH=<3PyScheme>`; cpp: pass the exe path |
| **Cross-port differential** | cppScheme2 vs pyScheme agree on macro programs | `cd scheme-tests/cross-port-tests && python diff.py` (add `--oracle chibi`) |
| **Fuzzer** | generated syntax-rules programs, cross-port (+ chibi) | `python fuzz.py --n 50 --seed 1` (add `--fast --oracle chibi`) |
| **Metamorphic property tests** | numeric / datum / ordering / string-UTF8 / eval properties — the *property* is the oracle, so they catch bugs BOTH ports share | `python -m pyscheme application-tests/property-tests/<name>.scm` (or the cppscheme2 exe). Names: `metamorphic-{numbers,datums,compare,strings,eval}` |
| **ecraven correctness sweep** | ~55 Gabriel/Gambit benchmarks, cpp vs py | `cd scheme-tests/application-tests/ecraven-r7rs-benchmarks && bash correctness-sweep.sh 600` |
| **GC white-box** (49 cases) | cppScheme2 generational GC internals | run `4CPPScheme2/build/Release/gc_test.exe` |
| **Coverage** | line/branch coverage per port | py: `python -m coverage run -m pyscheme -T <tests>` then `coverage report`; cpp: `pwsh -File 4CPPScheme2/coverage.ps1` |
| **CI (GitHub Actions)** | fast subset on every push; full battery + coverage nightly | automatic on push; view in each repo's Actions tab |
| **Pre-push hooks** | fast subset, locally, before every push | automatic on `git push` (enable: `sh hooks/install.sh`); run by hand: `sh hooks/pre-push` |

## Known-open bugs (why some metamorphic tests `xfail`)

These are documented, parked (not yet fixed). The metamorphic testers that expose
them fail *on purpose* until they're fixed:

1. **complex inf/nan write doubles the sign** — `(number->string (make-rectangular 3.0 +inf.0))` → `"3.0++inf.0i"` (not re-readable). Both ports.
2. **bignum-rational literal reader uses int64** — `(string->number "1/<bignum>")` → `#f`. cppScheme2 (`metamorphic-numbers` xfails on cpp).
3. **`write` doesn't bar-quote `@` / `.9t` symbols** — they write bare and don't re-read. Both ports (`metamorphic-datums` xfails on both).
4. **`earley` benchmark crashes** — cppScheme2.

The both-ports bugs (1 and 3) are also **pinned as SRFI-64 `test-expect-fail` cases** in
`application-tests/property-tests/known-open-bugs.scm` (run via `(srfi 64)`, needs
`-L <repo>/SRFI`). Each reports **XFAIL** today; when a bug is fixed the round-trip
starts passing and the harness reports **XPASS** — the cue to remove the pin.
Caveat: `run-tests.sh` only greps `0 failed`, so it marks the file `ok` whether the
pins XFAIL or XPASS — surfacing an XPASS as `FIXED!` is left to the `]tests` rework
(see backlog #9 / the SRFI-64 migration), which runs SRFI-64 files in-process and can
read the runner's xpass-count directly.

## Coming (backlog #9): one front-end for all of it

The end state is a single declarative test registry that both the REPL (`]suites`)
and Cherry (a checklist) read, so running any/all tests is point-and-click and no
one has to remember these invocations. This catalog + `run-all-tests.sh` are the
precursor and the source the registry will draw from.
