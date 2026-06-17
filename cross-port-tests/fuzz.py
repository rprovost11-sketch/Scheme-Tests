#!/usr/bin/env python3
"""cross-port-tests/fuzz.py -- grammar-based differential macro fuzzer (#4c).

Generates random but *valid-by-construction* syntax-rules programs, runs each
through pyScheme, cppScheme2, and (optionally) chibi via the diff.py machinery,
and reports where they disagree.  Validity-by-construction matters: a fully
random generator produces mostly parse errors, where divergence is noise.  Here
each program is a macro definition plus a USE built to match one of its clauses,
with templates referencing only the captured pattern variables -- so the
program runs to a value, and a divergence is a real macro-expansion bug.

The generator targets the ellipsis / hygiene machinery (nested and double-splice
ellipsis, multiple same-depth vars, broadcast, fixed prefix/suffix, vectors,
dotted tails, hygienic temporaries, recursion) -- the corners where the hand-
ported expanders are most likely to drift apart.

Findings are bucketed by severity:
  VALUE  -- ports produced different output            (worst)
  EXIT   -- one port errored / crashed, the other not
  SHARED -- ports agree with each other but differ from chibi  (needs --oracle)
  ERRMSG -- both errored, different message             (lowest; reported last)

Each unique finding's program is written to fuzz-findings/ for triage.

Usage:
    python fuzz.py                      # 200 programs, default seed, cross-port
    python fuzz.py --n 1000 --seed 7    # more programs, fixed seed (repeatable)
    python fuzz.py --oracle chibi       # also catch bugs BOTH ports share
    python fuzz.py --allow-mismatch     # also emit unequal-length ellipsis uses
                                        #   (rediscovers F1; off by default)
"""
import argparse
import os
import random
import sys
import tempfile

import diff   # sibling module: run_file, run_chibi, Run, PY_DIR, CPP_EXE

FINDINGS_DIR = os.path.join(diff.HERE, "fuzz-findings")
VARS = ["a", "b", "c", "d", "e", "f", "g", "h"]


def datum(rng):
    """A self-evaluating, write-stable datum (no unbound-variable hazard)."""
    return str(rng.randint(0, 99))


def group(rng, lo=0, hi=4):
    return [datum(rng) for _ in range(rng.randint(lo, hi))]


# --- shape generators: each returns (source, note) -------------------------
# A shape builds a one- or few-clause macro and a matching (write (m ...)) use.

def _defmac(clauses):
    body = "\n    ".join("(%s %s)" % (p, t) for p, t in clauses)
    return "(define-syntax m\n  (syntax-rules ()\n    %s))\n" % body


def shape_zip(rng, allow_mismatch):
    """Two same-depth ellipsis vars combined in one template (the F1 corner)."""
    n = rng.randint(1, 4)
    a = group(rng, n, n)
    m = n if not (allow_mismatch and rng.random() < 0.5) else rng.randint(0, n + 2)
    b = group(rng, m, m)
    src = _defmac([("(_ (a ...) (b ...))", "(list (list a b) ...)")])
    src += "(write (m (%s) (%s)))(newline)\n" % (" ".join(a), " ".join(b))
    return src, "zip same-depth |a|=%d |b|=%d" % (n, m)


def shape_flatten(rng, _am):
    """Double-splice: (list a ... ...) flattens one nesting level."""
    groups = [group(rng, 0, 3) for _ in range(rng.randint(1, 4))]
    src = _defmac([("(_ (a ...) ...)", "(list a ... ...)")])
    src += "(write (m %s))(newline)\n" % " ".join("(%s)" % " ".join(g) for g in groups)
    return src, "flatten %d groups" % len(groups)


def shape_transpose(rng, _am):
    """Nested ellipsis preserved in the template: ((a ...) ...)."""
    groups = [group(rng, 1, 3) for _ in range(rng.randint(1, 3))]
    src = _defmac([("(_ (a ...) ...)", "(list (list a ...) ...)")])
    src += "(write (m %s))(newline)\n" % " ".join("(%s)" % " ".join(g) for g in groups)
    return src, "nested-regroup %d groups" % len(groups)


def shape_fold(rng, _am):
    """Inner fold over a nested ellipsis: ((a ...) ...) -> ((+ a ...) ...)."""
    groups = [group(rng, 1, 4) for _ in range(rng.randint(1, 3))]
    src = _defmac([("(_ (a ...) ...)", "(list (+ a ...) ...)")])
    src += "(write (m %s))(newline)\n" % " ".join("(%s)" % " ".join(g) for g in groups)
    return src, "nested-fold %d groups" % len(groups)


def shape_broadcast(rng, _am):
    """Depth-0 var replicated across a depth-1 ellipsis."""
    x = datum(rng)
    ys = group(rng, 0, 5)
    src = _defmac([("(_ x (a ...))", "(list (cons x a) ...)")])
    src += "(write (m %s (%s)))(newline)\n" % (x, " ".join(ys))
    return src, "broadcast |a|=%d" % len(ys)


def shape_fixed_tail(rng, _am):
    """Ellipsis with a fixed prefix and/or suffix pattern."""
    pre = datum(rng)
    mid = group(rng, 0, 4)
    suf = datum(rng)
    src = _defmac([("(_ p a ... s)", "(list p (list a ...) s)")])
    src += "(write (m %s %s %s))(newline)\n" % (pre, " ".join(mid), suf)
    return src, "fixed prefix+suffix |mid|=%d" % len(mid)


def shape_vector(rng, _am):
    """Vector pattern + vector template with ellipsis."""
    xs = group(rng, 0, 5)
    src = _defmac([("(_ #(a ...))", "(vector a ... a ...)")])
    src += "(write (m #(%s)))(newline)\n" % " ".join(xs)
    return src, "vector dup |a|=%d" % len(xs)


def shape_dotted(rng, _am):
    """Dotted tail pattern + improper-list template via quote."""
    head = datum(rng)
    tail = group(rng, 0, 3)
    src = _defmac([("(_ (a . b))", "(cons 'a 'b)")])
    if tail:
        use = "(%s %s)" % (head, " ".join(tail))
    else:
        use = "(%s)" % head
    src += "(write (m %s))(newline)\n" % use
    return src, "dotted tail |tail|=%d" % len(tail)


def shape_recursive_or(rng, _am):
    """Recursive macro with a hygienic temporary; sometimes feed a colliding
    user identifier of the same name as the temporary."""
    n = rng.randint(0, 5)
    args = [rng.choice(["#f", datum(rng)]) for _ in range(n)]
    src = ("(define-syntax m\n  (syntax-rules ()\n"
           "    ((_) #f)\n    ((_ e) e)\n"
           "    ((_ e1 e2 ...) (let ((t e1)) (if t t (m e2 ...))))))\n")
    if rng.random() < 0.5:
        src += "(define t %s)\n" % datum(rng)   # collide with the macro's `t`
    src += "(write (m %s))(newline)\n" % " ".join(args)
    return src, "recursive-or n=%d" % n


def shape_let_star(rng, _am):
    """Recursive let* macro; later bindings reference earlier ones."""
    k = rng.randint(0, 4)
    binds, names = [], []
    prev = None
    for i in range(k):
        nm = VARS[i]
        val = datum(rng) if prev is None or rng.random() < 0.5 else "(+ %s 1)" % prev
        binds.append("(%s %s)" % (nm, val))
        names.append(nm)
        prev = nm
    src = ("(define-syntax ml\n  (syntax-rules ()\n"
           "    ((_ () body ...) (begin body ...))\n"
           "    ((_ ((x v) rest ...) body ...) (let ((x v)) (ml (rest ...) body ...)))))\n")
    src += "(write (ml (%s) (list %s)))(newline)\n" % (
        " ".join(binds), " ".join(names) if names else "'ok")
    return src, "let* k=%d" % k


def shape_quasi_splice(rng, _am):
    """Quasiquote template with unquote-splicing of an ellipsis var."""
    xs = group(rng, 0, 5)
    src = _defmac([("(_ (a ...))", "`(start ,@(list a ...) end)")])
    src += "(write (m (%s)))(newline)\n" % " ".join(xs)
    return src, "quasi-splice |a|=%d" % len(xs)


def shape_nested_gen(rng, _am):
    """Macro-generating-macro that threads a token into the inner template."""
    tok = rng.choice(["hello", "tok", "zzz"])
    arg = datum(rng)
    src = ("(define-syntax gen\n  (syntax-rules ()\n"
           "    ((_ mac t)\n     (define-syntax mac\n"
           "       (syntax-rules () ((_ x) (list 't x)))))))\n")
    src += "(gen m1 %s)\n(write (m1 %s))(newline)\n" % (tok, arg)
    return src, "nested-gen tok=%s" % tok


def shape_pair_ellipsis(rng, _am):
    """Ellipsis over a 2-element sub-pattern: (_ (k v) ...)."""
    n = rng.randint(0, 4)
    pairs = [(datum(rng), datum(rng)) for _ in range(n)]
    src = _defmac([("(_ (k v) ...)", "(list (list k v) ...)")])
    src += "(write (m %s))(newline)\n" % " ".join("(%s %s)" % p for p in pairs)
    return src, "pair-ellipsis n=%d" % n


def shape_wildcard(rng, _am):
    """Underscore wildcards in fixed positions are ignored, not bound."""
    a, mid, b = datum(rng), datum(rng), datum(rng)
    src = _defmac([("(_ a _ b)", "(list a b)")])
    src += "(write (m %s %s %s))(newline)\n" % (a, mid, b)
    return src, "wildcard-mid"


def shape_arity_error(rng, _am):
    """Deliberate arity mismatch: a fixed-arity clause called with the wrong
    count must error -- a port-vs-oracle error-parity probe."""
    extra = rng.choice([[], [datum(rng)], [datum(rng), datum(rng)]])
    args = [datum(rng), datum(rng)] + extra if rng.random() < 0.5 else [datum(rng)]
    src = _defmac([("(_ a b)", "(list a b)")])
    src += "(write (m %s))(newline)\n" % " ".join(args)
    return src, "arity-error argc=%d" % len(args)


SHAPES = [shape_zip, shape_flatten, shape_transpose, shape_fold, shape_broadcast,
          shape_fixed_tail, shape_vector, shape_dotted, shape_recursive_or,
          shape_let_star, shape_quasi_splice, shape_nested_gen,
          shape_pair_ellipsis, shape_wildcard, shape_arity_error]


def classify(py, cpp, ch):
    """Cross-port mode: py-vs-cpp first, then a shared deviation vs chibi.
    Return (bucket, detail) or (None, None) if the engines agree."""
    if not py.behaves_like(cpp):
        kind = py.divergence_kind(cpp)
        return kind, "py rc=%d out=%r | cpp rc=%d out=%r" % (py.rc, py.out, cpp.rc, cpp.out)
    if ch is not None and not py.matches_oracle(ch):
        return "SHARED", "ports=%r (rc%d) | chibi=%r (rc%d)" % (py.out, py.rc, ch.out, ch.rc)
    return None, None


def main():
    ap = argparse.ArgumentParser(description="differential macro fuzzer")
    ap.add_argument("--n", type=int, default=200, help="number of programs (default 200)")
    ap.add_argument("--seed", type=int, default=1, help="RNG seed (default 1, repeatable)")
    ap.add_argument("--oracle", choices=["chibi"], help="also catch bugs both ports share")
    ap.add_argument("--fast", action="store_true",
                    help="fuzz cppScheme2 vs chibi only (both native, no slow Python "
                         "launches); pull in pyScheme ONLY to classify the cases that "
                         "flag (cpp-only vs shared).  Relies on the ports being "
                         "identical mirrors -- which the cross-port sweep confirms.")
    ap.add_argument("--allow-mismatch", action="store_true",
                    help="emit unequal-length ellipsis uses too (rediscovers F1)")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    py_argv = [sys.executable, "-m", "pyscheme"]
    cpp_argv = [diff.CPP_EXE]
    oracle = args.oracle == "chibi" or args.fast

    mode = ("fast: cpp-vs-chibi" if args.fast
            else "cross-port+chibi" if oracle else "cross-port")
    print("macro fuzzer: n=%d seed=%d  [%s]%s"
          % (args.n, args.seed, mode, "  [allow-mismatch]" if args.allow_mismatch else ""))

    buckets = {"VALUE": [], "EXIT": [], "SHARED": [], "ERRMSG": []}
    seen = set()
    tmpdir = tempfile.mkdtemp(prefix="macrofuzz-")

    for i in range(args.n):
        shape = rng.choice(SHAPES)
        src, note = shape(rng, args.allow_mismatch)
        cf = os.path.join(tmpdir, "p%05d.scm" % i)
        with open(cf, "w", encoding="utf-8") as f:
            f.write(src)

        if args.fast:
            # Fast loop: only the two native engines.  cpp stands in for "the
            # ports" (they are identical mirrors); chibi is ground truth.
            cpp = diff.run_file(cpp_argv, cf)
            ch = diff.run_chibi(cf)
            if ch is None or cpp.matches_oracle(ch):
                continue
            bucket = "VALUE" if cpp.out != ch.out else "EXIT"
            # Only now spend a pyScheme launch, to classify the finding.
            py = diff.run_file(py_argv, cf, cwd=diff.PY_DIR)
            klass = "cpp-only" if py.matches_oracle(ch) else "shared"
            detail = ("[%s] cpp rc=%d out=%r | chibi rc=%d out=%r | py rc=%d out=%r"
                      % (klass, cpp.rc, cpp.out, ch.rc, ch.out, py.rc, py.out))
            sig = (bucket, shape.__name__, klass, cpp.out, cpp.rc)
        else:
            py = diff.run_file(py_argv, cf, cwd=diff.PY_DIR)
            cpp = diff.run_file(cpp_argv, cf)
            ch = diff.run_chibi(cf) if oracle else None
            bucket, detail = classify(py, cpp, ch)
            if bucket is None:
                continue
            sig = (bucket, shape.__name__, py.out, cpp.out, py.rc, cpp.rc)

        if sig in seen:   # dedup so one bug class isn't reported 100×
            continue
        seen.add(sig)
        path = os.path.join(FINDINGS_DIR, "%s-%s-%05d.scm" % (bucket, shape.__name__, i))
        os.makedirs(FINDINGS_DIR, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(";;; fuzz finding [%s] %s (seed=%d i=%d)\n;;; %s\n\n%s"
                    % (bucket, shape.__name__, args.seed, i, detail, src))
        buckets[bucket].append((shape.__name__, note, detail, os.path.basename(path)))

    total = sum(len(v) for v in buckets.values())
    print("\n%d programs run, %d unique findings:" % (args.n, total))
    for b in ("VALUE", "EXIT", "SHARED", "ERRMSG"):
        if buckets[b]:
            print("\n  == %s (%d) ==" % (b, len(buckets[b])))
            for shp, note, detail, fname in buckets[b]:
                print("    %-16s %s" % (shp, note))
                print("        %s" % detail)
                print("        -> %s" % fname)
    if total == 0:
        print("  (no divergences)")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
