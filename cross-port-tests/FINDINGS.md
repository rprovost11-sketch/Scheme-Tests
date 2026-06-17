# cross-port findings

Divergences this harness has surfaced. Each is a bug in at least one port (the
two are mirror implementations, so identical input must behave identically).
Confirmed bugs get a quarantined repro under `known-bugs/` until fixed, then a
well-formed regression guard is promoted into `cases/`.

---

## F1 — ellipsis length-mismatch: out-of-bounds in both expanders

**Status:** open. **Repro:** `known-bugs/ellipsis-length-mismatch.scm`.
**Severity:** cppScheme2 high (memory-unsafe segfault + silently wrong data);
pyScheme medium (uncaught host exception, no clean diagnostic).

Two same-depth ellipsis pattern variables of unequal length used together in
one template — e.g.

```scheme
(define-syntax zp
  (syntax-rules () ((_ (a ...) (b ...)) (list (list a b) ...))))
```

Per R7RS 4.3.2 this is *an error*; chibi tolerates it by truncating to the
shorter sequence. The iteration is driven by the **first** ellipsis var, so the
bug only triggers when a **later** var is the shorter one:

| input | chibi (ref) | pyScheme | cppScheme2 |
|-------|-------------|----------|------------|
| `(zp (1 2) (10 20 30))` | `((1 10) (2 20))` | `((1 10) (2 20))` ✓ | `((1 10) (2 20))` ✓ |
| `(zp (1 2 3) (10 20))` | `((1 10) (2 20))` | `list index out of range` (host `IndexError`, rc 1) | `((1 10) (2 20) (3 #<unknown>))` (fabricated value, rc 0) |
| `(zp (1 2) ())` | `()` | `list index out of range` (rc 1) | **SIGSEGV (rc 139)** |

**Root cause (to confirm in code):** the template-instantiation loop iterates by
the first ellipsis var's match-count and indexes the others by the same count
without a bounds check. pyScheme's list indexing raises `IndexError` (leaks as a
location-less `pyscheme:` message instead of a Scheme syntax error);
cppScheme2 reads past the end of the shorter match vector — returning an
uninitialized `#<unknown>` in the mild case, dereferencing out of bounds (crash)
when the shorter var is empty.

**cppScheme2 result is nondeterministic — confirming memory-unsafety.** The
mild case (`(zp (1 2 3) (10 20))`) prints `(3 #<unknown>)` stably when run under
bash, but errors differently (`empty list () is not a valid expression`) when run
as a separate-pipe subprocess from the harness: the out-of-bounds read returns
whatever ambient memory holds, which depends on the invocation context. The
empty-var case crashes with Windows access violation `0xC0000005` (rc
3221225477; SIGSEGV / rc 139 on Linux). This is reading uninitialized/OOB memory,
not merely a wrong-answer logic bug.

**Fix target:** detect mismatched ellipsis match-counts during template
instantiation and raise a clean Scheme-level syntax error in *both* ports.
(Matching chibi's silent truncation is the alternative, but a diagnosed error is
the safer R7RS-conformant choice and easier to keep in lockstep across ports.)
Decide cross-port behavior once, implement identically, then promote a guard to
`cases/`.
