# Universal interpreter differ

A general N-interpreter **behaviour differ**, written in Scheme and run *by* the
interpreters themselves (the only cross-platform coordinator: Windows, Linux,
macOS, no shell). It treats a `.log` golden file as just another interpreter — a
*reference interpreter* whose recorded `{output, retval, error}` per REPL cycle is
replayed by `parse-log-file`. One engine then subsumes three tools by varying
`{interpreters, mode, strictness}`:

| Tool | = differ with |
|------|---------------|
| the `.log` golden test runner | reference = `.log`, subjects = cpp/py, strict |
| `chibi_diff` conformance | reference = `.log`, subject = chibi, coarse |
| cross-port diff / fuzz | peer mode over cpp+py, strict |

See the `universal-interpreter-differ` design note for the full rationale (why
this *supersedes* the `.log`→SRFI-64 migration for the golden battery).

## Files

- **`differ.scm`** — the engine. `load`ed (not imported) after the host's own
  `(import (scheme base) ...)`, mirroring `../cross-port-tests/cross-port-common.scm`.
  Needs the `parse-log-file` / `log-match?` primitives (both ports, ≥ the
  increment-1 commit).
- **`differ-selftest.scm`** — self-test. Run with cwd = this directory:
  - cppScheme2: `cppscheme2.exe differ-selftest.scm`
  - pyScheme: `PYTHONPATH=<3PyScheme> python -m pyscheme differ-selftest.scm`

  Exits 0 if every check passes. Uses mock (canned) interpreters to exercise
  classification independently of live execution, plus a real `.log` fixture
  driven through `parse-log-file`/`log-match?`.
- **`differ-validate.scm`** — reference-mode validation: the live in-process **host**
  runner (`eval-cycle` per cycle) vs the `.log` golden over a whole suite.
- **`sibling-driver.scm`** — the subprocess driver for the live **sibling** runner;
  reads `(input fold-case?)` specs on stdin, runs each through `eval-cycle` in one
  `(interaction-environment)`, writes `(output retval error timed-out?)` per cycle.
- **`differ-subprocess-validate.scm`** — peer validation of the in-process host vs a
  **same-port** subprocess sibling (should agree on every cycle; isolates the
  subprocess mechanism).
- **`differ-crossport-validate.scm`** — the **cross-port** demo: one port in-process
  (host) vs the **other** port as a subprocess sibling, peer, over a whole suite. The
  host is whichever port runs the script; the sibling is launched from the other
  port's exe argv. Run with cwd = this directory and `PYTHONPATH` set (the py child
  needs it; cpp ignores it):
  - cpp host / py sibling: `PYTHONPATH=<3PyScheme> cppscheme2.exe differ-crossport-validate.scm`
  - py host / cpp sibling: `PYTHONPATH=<3PyScheme> python -m pyscheme differ-crossport-validate.scm`

  Both ports are mirror implementations, so they agree on all but a small, fully
  explained set. Over the feature suite (4897 cycles), **strict** comparison flags 8
  cycles — 2 from `~/.pyschemerc` defining `fold-left` (cpp has no rc) and 6 from
  OS/codec error-**message tails** the golden itself marks as varying — symmetric in
  both directions. **Coarse** (`DIFFER_STRICT=0`: output + errored-or-not) drops the 6
  cosmetic error-wording cases, isolating the 2 genuine rc-pollution divergences.

## Design (the core is deliberately tiny)

The core never inspects a result; it only feeds pairs of results to a
caller-supplied `compare`. All variability lives outside it:

- **interpreter descriptor** `(make-interp name family run)` — `run : item -> result`.
  A `.log` playback interpreter (`make-log-playback`) replays recorded channels;
  live execution runners arrive in **increment 3**.
- **source** — a list of items. For `.log`, `(log-source path)` = the parsed
  entries `(input output retval error fold-case?)`.
- **mode** — `'peer` (partition into agreement classes; >1 class ⇒ divergence) or
  `'reference` (first interpreter is the oracle; flag disagreers).
- **compare** — a predicate on two results. Provided strategies for cycle results:
  `cycle-golden-match?` (reference vs a `.log` golden, honouring `==> X or ==> Y`,
  `%%% *`, `%any-error%`, `%optional-error%` via `log-match?`), `cycle-strict=?`
  (mirror-family), `cycle-coarse=?` (cross-family: output + errored-or-not only).

`differ-run` returns a list of `<verdict>` records; `differ-report` prints the
divergences and returns `#t` when everything agrees.

## Increments

1. ✅ `.log` parse + match primitives (`parse-log-file`, `log-match?`) — both ports.
2. ✅ **differ core** — gather + classify (peer/reference, strict/coarse). *(this dir)*
3. live runners: host in-process via `make-environment` per cycle; others via
   `run-process` subprocess with a marker driver.
4. ✅ retrofit cross-port diff / fuzz onto the engine (peer, whole-program) —
   `../cross-port-tests/{diff,fuzz}.scm` now `load` `differ.scm` and classify via
   `differ-run` / `classify-item` over `#(out err rc)` results.
5. ◑ wire `]suites` (golden battery via differ reference-mode; chibi/Chez variants).
   - ✅ `--no-rc` flag (both ports) → pristine global, and `differ-battery.scm` runs a
     `.log` suite as differ(reference = golden, subject = in-process host, compare =
     `.log` match). Wired as `]suites differ-feature` (cwd = the suite dir + `--no-rc`);
     reproduces the golden verdict 4897/4897 (feature) + 81/81 (regression), both ports.
   - ☐ remaining: `.run` reports (per-channel `log-match-detail`), chibi/Chez coarse
     conformance variants.
6. retire `chibi_diff.py` (subsumed).
