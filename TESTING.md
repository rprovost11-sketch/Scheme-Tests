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

Parked bugs are marked `test-expect-fail` (report **XFAIL**, which does NOT fail
the run) until fixed; when fixed the case passes (**XPASS** — the cue to promote
it to a regression test).

**Remaining (both cppScheme2-only):**

1. **bignum-rational literal reader uses int64** — `(string->number "1/<bignum>")` → `#f`. cppScheme2 only.
2. **`earley` benchmark crashes** — cppScheme2 (ecraven sweep; not a metamorphic tester).

`metamorphic-numbers.scm` feature-detects bug 1 via a probe
(`reader-handles-bignum-rational?`) and expect-fails exactly the bignum-rational
roundtrips: py 6606/0, cpp 6442 pass + **164 XFAIL**.  A failure NOT covered by a
detector is a real, unexpected **FAIL**.

**Fixed & promoted (2026-06-19):**

- **complex inf/nan write doubling** (`"3.0++inf.0i"`, both ports) — fixed in
  `number->string`; guarded in `log-tests/regression-tests/02-printer.log`.
- **`write` not bar-quoting `@` / `.9t` symbols** (both ports) — fixed in the
  printer's needs-bar-quote predicate; guarded in `02-printer.log`.
  `metamorphic-datums.scm` (which feature-detects this) self-promoted to a clean
  pass (both ports now 500/0, no XFAIL).  `known-open-bugs.scm` no longer pins
  any both-ports bug (sanity round-trip only; ready for the next one).
