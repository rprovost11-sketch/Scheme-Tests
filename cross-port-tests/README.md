# cross-port-tests — differential macro harness

Feeds identical macro-heavy programs to **both** ports — pyScheme (Python) and
cppScheme2 (C++) — and compares their behavior. The two ports are *mirror*
implementations of the same language, so any behavioral divergence on identical
input is, by construction, a bug in at least one of them. **No expected values
are stored**: the oracle is "the other port".

This automates the hand process that caught 3 cppScheme2-only bugs during the
benchmark work. It is part **#4b** of the macro-implementation bug-detection
effort. Its sibling pieces — expander mark-invariant assertions (#4a) and a
differential fuzzer against chibi/Chez to catch bugs *both* ports share (#4c) —
are tracked separately; the `--oracle chibi` hint here is the first toe into #4c.

## Why its own category (a sister of `cli-tests/` and `application-tests/`)

The subject under test is **cross-port behavioral parity of macro expansion** —
a shared, port-agnostic, black-box property — so it belongs in `scheme-tests/`,
not in either port's tree. It is not a `.log` suite (it diffs two live processes,
not `>>> expr` ⇒ `==> value`), and not an `application-tests/` program (the pass
criterion is *agreement between ports*, not a self-checked answer).

## What is compared — and why the streams are kept apart

Each case runs in **file mode** on both ports. File mode prints only the
program's explicit output, with errors on stderr — so the streams separate
cleanly into *behavior* vs *diagnostics*:

- **stdout** — the program's written values. Compared byte-for-byte; this is
  where an evaluation divergence shows. Reported as a `VALUE` divergence.
- **exit code** — compared exactly; catches "one port errored, the other
  didn't". Reported as an `EXIT` divergence.
- **stderr** — only its *normalized core* error message is compared. The ports
  legitimately differ in error **chrome** (pyScheme prints the file path + a
  source-line echo + a caret; cppScheme2 prints just the message), so the chrome
  is stripped first. A surviving difference means the ports took different error
  paths — still a real finding, reported as an `ERRMSG` divergence (less severe
  than `VALUE`).

Keeping the streams apart is essential: without it, *every* error case is a
false positive, because the two ports' error chrome always differs.

## Running

The harness is now **pure Scheme** — `diff.scm` and `fuzz.scm`, sharing the
compare/normalize engine in `cross-port-common.scm`. They depend only on the
interpreter (no python), launching each port via `(run-process …)`:

    ]suites cross-port        # the curated cases/ corpus
    ]suites fuzz-smoke        # generated programs (FUZZ_N env overrides the count)

Both are **py-hosted** (registry: `ports py`): the suite runs inside pyScheme,
which lets its py child inherit `PYTHONPATH` from the listener; the cpp side is
the sibling exe by a known relative path (`../../4CPPScheme2/build/Release/
cppscheme2.exe`). The comparison is symmetric, so one host suffices. Exit status
is non-zero on any divergence, so they gate like the cli-tests.

To run a driver directly (from this directory, hosted on pyScheme):

    <pyscheme> diff.scm
    FUZZ_N=200 FUZZ_SEED=7 <pyscheme> fuzz.scm

## The chibi oracle (not yet ported)

The bare cross-port diff cannot catch a bug **both** ports share — if they are
wrong the same way, they still agree. A third engine (chibi-scheme, the R7RS
reference) consulted on every case adjudicates *which* port is wrong on a
divergence, and flags a **`SHARED-DEVIATION`** on parity. The Scheme drivers do
**not** implement this yet; the original Python chibi differ (`chibi_diff.py`)
remains as the manual tool for that, pending a Scheme port.

## The fuzzer (`fuzz.scm`)

`diff.scm` checks a curated corpus; `fuzz.scm` generates random ones. It emits
*valid-by-construction* `syntax-rules` programs — a macro plus a USE built to
match one of its clauses, templates referencing only captured pattern variables
— so each program runs to a value and a divergence is a real bug, not a parse
error. The shapes target the ellipsis/hygiene machinery (double-splice, nested
and folded ellipsis, multiple same-depth vars, broadcast, fixed prefix/suffix,
vectors, dotted tails, hygienic temporaries, recursion).

A seeded LCG drives generation (deterministic per seed; the exact sequence
differs from the old Python RNG, which does not matter). `N`/`SEED` default to
30/1 and are overridden by the `FUZZ_N`/`FUZZ_SEED` environment variables
(interpreters reject extra argv, so CI's larger run sets `FUZZ_N=200`). On a
divergence the offending program is printed to stdout for triage; a clean run
finds nothing on valid programs.

`--fast` exploits the ports being identical mirrors (the cross-port sweep finds
0 divergences across thousands of valid programs): it fuzzes only the two native
engines — cppScheme2 as stand-in for "the ports", chibi as ground truth — and
launches pyScheme *only* to classify the cases that flag (`cpp-only` if pyScheme
matches chibi, `shared` if it too deviates). Measured aside: pyScheme is not the
bottleneck (~0.03 s/launch); the chibi oracle's per-program process+driver is, so
`--fast` is a ~10% win and a cleaner port-vs-reference hunt. The big lever for
very large campaigns would be batching chibi (one process for many programs, as
`chibi_diff.py` does) — not yet implemented here.

## The corpus (`cases/`)

Each case is a self-contained program that **writes its own result(s)**, so a
divergence is legible as differing output. Every case is also runnable directly
on either port for debugging (`cppscheme2.exe cases/foo.scm`). Cases must be
valid R7RS — a malformed case makes a "divergence" the author's bug, not a
port's — so new cases are validated against chibi before being added.

The seed corpus covers hygiene (capture avoidance, the A1f generated-binding
case), nested/fixed-tail/vector/dotted ellipsis patterns, custom ellipsis and
the `(... ...)` escape, literal-identifier matching, recursive and
mutually-recursive transformers, and `let-syntax`/`letrec-syntax` scoping. It
passes clean today (Group A hygiene is complete) and so doubles as a regression
guard; the discovery value grows as adversarial cases are added.
