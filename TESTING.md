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

## Known-open bugs (handled as SRFI-64 `test-expect-fail`)

These are documented, parked (not yet fixed). The metamorphic testers that expose
them now run under **SRFI 64** and mark the affected cases `test-expect-fail`, so
they report **XFAIL** (an expected failure — does NOT fail the run) instead of FAIL:

1. **complex inf/nan write doubles the sign** — `(number->string (make-rectangular 3.0 +inf.0))` → `"3.0++inf.0i"` (not re-readable). Both ports.
2. **bignum-rational literal reader uses int64** — `(string->number "1/<bignum>")` → `#f`. cppScheme2 only.
3. **`write` doesn't bar-quote `@` / `.9t` symbols** — they write bare and don't re-read. Both ports.
4. **`earley` benchmark crashes** — cppScheme2 (ecraven sweep; not a metamorphic tester).

How each tester pins its bug (all **feature-detected**, not port-hardcoded, so they
self-promote to a clean pass the moment a port fixes the bug — no XPASS noise):

- `known-open-bugs.scm` — deterministic pins for the both-ports bugs (1 and 3); 1 pass + 3 XFAIL.
- `metamorphic-numbers.scm` — detects bug 2 via a probe (`reader-handles-bignum-rational?`)
  and expect-fails exactly the bignum-rational roundtrips: py 6606/0, cpp 6442 pass + **164 XFAIL**.
- `metamorphic-datums.scm` — detects bug 3 via `symbol-roundtrips?` and expect-fails datums
  containing a non-roundtripping symbol: both ports 498 pass + **2 XFAIL**.

A failure NOT covered by a detector is a real, unexpected **FAIL**. All of these need
`-L <repo>/SRFI` so `(srfi 64)` resolves (the `scheme` kind in `run-tests.sh` passes it).

Caveat: `run-tests.sh` only greps `0 failed`, so it marks a file `ok` whether its pins
XFAIL or XPASS — surfacing an XPASS as `FIXED!` is left to the `]tests` rework (see
backlog #9 / the SRFI-64 migration), which runs SRFI-64 files in-process and can read
the runner's xpass-count directly. The manifest's per-port `xfail` column is therefore
no longer needed for these (the expectation lives inside each test now).

## Coming (backlog #9): one front-end for all of it

The end state is a single declarative test registry that both the REPL (`]suites`)
and Cherry (a checklist) read, so running any/all tests is point-and-click and no
one has to remember these invocations. This catalog + `run-all-tests.sh` are the
precursor and the source the registry will draw from.
