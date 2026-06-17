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
    python diff.py                      # all cases in cases/
    python diff.py cases/06-recursive-or.scm   # one (or several) cases
    python diff.py -v                   # show stdout even for parity cases
    python diff.py --oracle chibi       # on divergence, hint which port is wrong

The harness path-discovers both interpreters relative to its own location
(`../../3PyScheme`, `../../4CPPScheme2/build/Release/cppscheme2.exe`); override
with `--py "<invocation>"` / `--cpp "<invocation>"`. Exit status is non-zero if
any case diverges, so it gates like the cli-tests.

`--oracle chibi` runs the case body through chibi-scheme on stdin (its file
compiler mishandles a macro-generated `define-syntax` with empty literals) and
best-effort strips REPL prompt/warning chrome. Treat its verdict as a hint, not
gospel — hardening it is part #4c.

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
