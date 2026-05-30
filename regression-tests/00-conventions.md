# Regression tests

The third test layer, alongside **feature-tests/** and **R7RS-Compliance-Tests/**.

## What each layer answers

| Layer | Question | Organizing axis |
|-------|----------|-----------------|
| `R7RS-Compliance-Tests/` | Do we match R7RS? | spec `chapter.section.subsection` |
| `feature-tests/` | Do our features behave as intended? | concept, fundamental → abstract |
| `regression-tests/` | Did a specific bug we already fixed come back? | subsystem, fundamental → abstract |

A regression test is a **tripwire pinned to a past defect**, not coverage. Keep each one a
minimal reproducer.

## Routing rule — where does a fixed bug's guard go?

When you fix a bug, ask: *was it a deviation from R7RS?*

1. **Yes — spec deviation** → the **compliance** suite already guards it (add the missing
   spec case there if needed). Do NOT also add it here; the compliance test *is* the
   regression guard.
2. **No — implementation-specific, observable from Scheme** → put it **here**. Examples:
   reader/printer quirks, evaluator edge cases, GC behavior visible from Scheme, macro
   hygiene, error-message wording, listener/REPL behavior, non-spec extensions.
3. **No — internal / not observable from Scheme** (raw GC invariants, C++ data structures,
   crashes with no Scheme-level symptom) → goes in the C++ layer,
   `4CPPScheme2/undercarriage-tests/gc_test.cpp`, not here.

So this suite is specifically for **Scheme-observable, non-spec** regressions.

## File organization

Files are grouped by **subsystem**, numeric-prefixed to force fundamental → abstract order
(alphabetical sort = intended order). The buckets below are pre-seeded as stubs (header +
how-to, no cases yet); add cases to the matching file as bugs are fixed, and add a new
numbered bucket if a subsystem isn't covered:

```
01-reader.log        lexer / datum syntax
02-printer.log       external representation, write/display round-trips
03-evaluator.log     special forms, tail calls, continuations, dynamic-wind
04-gc.log            GC bugs observable from Scheme (internals -> gc_test.cpp)
05-macros.log        syntax-rules, hygiene, expansion
06-numerics.log
07-data-types.log    strings, chars, vectors, bytevectors, lists
08-libraries.log     import / define-library
09-errors.log        exceptions, guard, error objects
10-listener.log      REPL / listener-command behavior
```

Within a file, order tests **chronologically** (oldest bug first) so the file reads as a
timeline for that subsystem.

## Per-test provenance annotation

The chronological / bug dimension lives in an annotation on each test, NOT in the filename.
A regression test with no provenance is far less useful six months later. Format:

```
; REG <date> — <commit-or-issue> — <one-line: what broke>
; Symptom: <what the user saw before the fix>
>>> (the minimal reproducer)
==> expected
```

## Running

The session-log format is identical to the other suites; compliance "extras"
(`==> X or ==> Y` alternatives, `%%% %any-error%`) are available here too.

```
]regression                     run every *.log in this directory
]regression 03-evaluator.log    run one file
]regression 03 06               run files in [03, 06) by filename
```

The interpreter is rebooted before each file. A run report is written to `scheme-tests/runs/`
(same place as the other suites) named `yyyy-mm-dd-hhmmss-regression-<interpreter>.run`, where
`<interpreter>` is `PyScheme` or `CPPScheme2`. Feature and compliance runs use the same
pattern with their own suite tag (`feature`, `compliance`).
