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

    # from this directory
    python diff.py                      # all cases in cases/ (cross-port only)
    python diff.py cases/06-recursive-or.scm   # one (or several) cases
    python diff.py -v                   # show stdout even for parity cases
    python diff.py --oracle chibi       # add chibi as a third engine (see below)

The harness path-discovers both interpreters relative to its own location
(`../../3PyScheme`, `../../4CPPScheme2/build/Release/cppscheme2.exe`); override
with `--py "<invocation>"` / `--cpp "<invocation>"`. Exit status is non-zero if
any case diverges, so it gates like the cli-tests.

## The chibi oracle (`--oracle chibi`)

The bare cross-port diff cannot catch a bug **both** ports share — if they are
wrong the same way, they still agree. `--oracle chibi` adds chibi-scheme (the
R7RS reference) as a third engine consulted on **every** case, so:

- on a cross-port **divergence**, it adjudicates *which* port is wrong;
- on cross-port **parity**, it still checks the agreed answer against chibi — a
  mismatch is a **`SHARED-DEVIATION`** (a bug both ports share, or a chibi
  quirk), which the diff alone would silently pass.

chibi runs each case via a driver that `eval`s the case's forms one-by-one in an
`interaction-environment`, so the program's own output lands on clean stdout
(no REPL prompt chrome) and chibi's file-compiler quirk with macro-generated
`define-syntax` is sidestepped. Because chibi is a *different* implementation,
only its **output and errored-or-not** are compared, never its error *wording*.

## The fuzzer (`fuzz.py`)

`diff.py` checks a curated corpus; `fuzz.py` generates random ones. It emits
*valid-by-construction* `syntax-rules` programs — a macro plus a USE built to
match one of its clauses, templates referencing only captured pattern variables
— so each program runs to a value and a divergence is a real bug, not a parse
error. The shapes target the ellipsis/hygiene machinery (double-splice, nested
and folded ellipsis, multiple same-depth vars, broadcast, fixed prefix/suffix,
vectors, dotted tails, hygienic temporaries, recursion).

    python fuzz.py                      # 200 programs, seed 1, cross-port
    python fuzz.py --n 1000 --seed 7    # more, fixed seed (repeatable)
    python fuzz.py --oracle chibi       # also catch bugs BOTH ports share
    python fuzz.py --allow-mismatch     # emit unequal-length ellipsis uses too

Findings are deduped by signature and bucketed VALUE > EXIT > SHARED > ERRMSG;
each unique one's program is written to `fuzz-findings/` (gitignored) for triage.
A clean run finds nothing on valid programs; `--allow-mismatch` rediscovers F1,
which is how the fuzzer's bug-finding is self-checked.

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
