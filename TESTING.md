# Testing catalog

Every test in the arsenal, and exactly how to run it. The goal is **parity**:
either party can run *all* the tests, so neither has a test the other can't run.

Paths below are relative to the `Lisp/` parent directory (the repos sit as
siblings: `scheme-tests/`, `3PyScheme/`, `4CPPScheme2/`, `SRFI/`). pyScheme is
stdlib-only; cppScheme2 tests need a Release build (`build/Release/cppscheme2.exe`).

## Run everything from one place — `]suites`

The whole arsenal is registered in **`test-suites.scm`** (the single source of
truth) and run through the interpreter's **`]suites`** command — in the REPL on
either port, or from **Cherry's "Test Suites..." dialog** (which renders its
checklist from `]suites list`). Adding a test = one registry entry; it then
appears everywhere automatically.

```
]suites              # show the catalog (name · aliases · kind · ports · desc)
]suites list         # same
]suites all          # run every suite
]suites <tok> ...    # run by suite name, short alias (mc), or category (metamorphic)
]suites all-slow     # slow variant of each suite that has one (e.g. compliance soak)
```

Suites run by **kind**: `log` (the `.log` batteries) and `scheme` (the SRFI-64
property suites) run via the interpreter; `external` tools (gc_test, the
differential/fuzz harnesses) are spawned. Known-open bugs report **XFAIL**
(expected) and do not fail the run; if a pinned bug starts passing it shows as
**XPASS** ("promote it"). `]suites` needs `-T <scheme-tests>` set (option, env
`SCHEME_TESTS_DIR`, or `]scheme-tests`).

## The individual tests (direct invocations)

Each is reachable through `]suites <name>`; the direct invocation is also listed.

| Test (suite name) | What it checks | Direct invocation |
|---|---|---|
| **feature / compliance / regression** (~11.9k cases) | R7RS conformance + features + regression tripwires, in-process | `]feature` / `]compliance` / `]regression` (or `]suites battery`) |
| One `.log` file | a single suite file | `]feature test031-ports.log` (etc.) |
| **cli-tests** (15 checks) | argv, exit codes, stdin, `.run` reports | `bash scheme-tests/cli-tests/run.sh "<interp>"` — py needs `PYTHONPATH=<3PyScheme>`; cpp: pass the exe path |
| **cross-port** | cppScheme2 vs pyScheme agree on macro programs | `cd scheme-tests/cross-port-tests && python diff.py` (add `--oracle chibi`) |
| **fuzz-smoke** | generated syntax-rules programs, cross-port (+ chibi) | `python fuzz.py --n 50 --seed 1` (add `--fast --oracle chibi`) |
| **metamorphic-{numbers,datums,compare,strings,eval}** | numeric / datum / ordering / string-UTF8 / eval properties — the *property* is the oracle, so they catch bugs BOTH ports share | `<interp> -L <repo>/SRFI application-tests/property-tests/<name>.scm` |
| **known-open-bugs** | SRFI-64 pins for the parked known-open bugs | `<interp> -L <repo>/SRFI application-tests/property-tests/known-open-bugs.scm` |
| **ecraven correctness sweep** | ~55 Gabriel/Gambit benchmarks, cpp vs py | `cd scheme-tests/application-tests/ecraven-r7rs-benchmarks && bash correctness-sweep.sh 600` |
| **gc_test** (white-box GC, 49 cases) | cppScheme2 generational GC internals | run `4CPPScheme2/build/Release/gc_test.exe` |
| **Coverage** | line/branch coverage per port | py: `python -m coverage run -m pyscheme -T <tests>` then `coverage report`; cpp: `pwsh -File 4CPPScheme2/coverage.ps1` |
| **CI (GitHub Actions)** | fast subset on every push; full battery + coverage nightly | automatic on push; view in each repo's Actions tab |
| **Pre-push hooks** | fast subset, locally, before every push | automatic on `git push` (enable: `sh hooks/install.sh`); run by hand: `sh hooks/pre-push` |

The SRFI-64 suites need `-L <repo>/SRFI` so `(srfi 64)` resolves; the `scheme`
kind in `]suites` passes it automatically from each suite's `(libs ...)`.

## Known-open bugs (handled as SRFI-64 `test-expect-fail`)

These are documented, parked (not yet fixed). The metamorphic testers that expose
them run under **SRFI 64** and mark the affected cases `test-expect-fail`, so they
report **XFAIL** (an expected failure — does NOT fail the run) instead of FAIL:

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

A failure NOT covered by a detector is a real, unexpected **FAIL**. When a port
fixes a bug, the affected pin starts passing → `]suites` surfaces it as **XPASS**
(read from the SRFI-64 runner's xpass-count), the cue to remove the pin.
