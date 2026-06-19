#!/usr/bin/env bash
#
# cli-tests/run.sh — shell-level tests for the Scheme interpreters' CLI and
# process-boundary behavior: things the .log suites cannot test because they
# run *inside* an already-launched interpreter.  See README.md.
#
# Usage:  bash run.sh "<interpreter invocation>"
#   (cd ../../../3PyScheme && bash ../scheme-tests/cli-tests/run.sh "python -m pyscheme")
#   bash run.sh "/d/SWDEV/Languages/Lisp/4CPPScheme2/build/Release/cppscheme2.exe"
#
# The invocation is passed verbatim (may contain spaces, e.g. "python -m
# pyscheme").  Exits non-zero if any check fails.  Kept deliberately cheap —
# a handful of process launches — so it can run on every change.

set -u

INTERP="${1:?usage: run.sh \"<interpreter invocation>\"}"

pass=0
fail=0

ok() { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
ng() {
  fail=$((fail + 1))
  printf '  FAIL  %s\n' "$1"
  shift
  for line in "$@"; do printf '          %s\n' "$line"; done
}

# run <stdin> <argv...>  — launch the interpreter with <stdin> piped in and
# the remaining args as argv; capture combined stdout+stderr in OUT, exit in RC.
# $INTERP is intentionally unquoted so "python -m pyscheme" word-splits into
# program + flags; "$@" keeps each interpreter arg as one word.
run() {
  local input="$1"
  shift
  OUT="$(printf '%s' "$input" | $INTERP "$@" 2>&1)"
  RC=$?
}

assert_contains() { case "$OUT" in *"$2"*) ok "$1" ;; *) ng "$1" "expected output to contain: $2" "got: $OUT" ;; esac; }
assert_absent()   { case "$OUT" in *"$2"*) ng "$1" "expected output NOT to contain: $2" "got: $OUT" ;; *) ok "$1" ;; esac; }
assert_rc()       { if [ "$RC" = "$2" ]; then ok "$1"; else ng "$1" "expected exit $2, got $RC" "output: $OUT"; fi; }

printf 'cli-tests against: %s\n\n' "$INTERP"

# ---- -e / --evaluate ----------------------------------------------------

run '' -e '(+ 1 2)'
assert_contains 'eval: -e evaluates an expression and prints its value' '==> 3'
assert_rc       'eval: -e exits 0 on success' 0
assert_absent   'eval: -e suppresses the startup banner' 'Welcome'

run '' -e '(define x 5)' -e 'x'
assert_contains 'eval: -e is repeatable and shares interpreter state' '==> 5'

# ---- stdin (read) -------------------------------------------------------

run '(1 2 3)
' -e '(read)'
assert_contains 'stdin: (read) reads a datum piped on stdin' '==> (1 2 3)'

run '' -e '(read)'
assert_contains 'stdin: (read) at EOF returns the eof object' '#<eof>'

# ---- argv rejection / exit codes ----------------------------------------

run '' -e '(+ 1 2)' some-target.scm
assert_rc       'argv: -e combined with a file target exits 2' 2
assert_contains 'argv: -e + target explains the conflict' 'cannot be combined'

# ---- .run report behavior -----------------------------------------------
# Build a throwaway tests-root (one all-pass feature file, one with a
# deliberate failure, one all-pass regression file), run two suites, and
# inspect the runs/ dir.  The interpreter resolves paths in native (Windows)
# form, so convert the temp dir from its MSYS path for the listener command.

FIX="$(mktemp -d)"
FIX_NATIVE="$(cygpath -m "$FIX" 2>/dev/null || printf '%s' "$FIX")"
mkdir -p "$FIX/log-tests/feature-tests" "$FIX/log-tests/regression-tests" "$FIX/runs"
printf '>>> (+ 1 2)\n\n==> 3\n'        > "$FIX/log-tests/feature-tests/a-allpass.log"
printf '>>> (* 6 7)\n\n==> 999\n'      > "$FIX/log-tests/feature-tests/b-hasfail.log"
printf '>>> (list 1 2)\n\n==> (1 2)\n' > "$FIX/log-tests/regression-tests/r-allpass.log"

# ]suites is registry-driven: give the fixture a minimal test-suites.scm
# defining the two log suites it runs (paths relative to this tests-root).
cat > "$FIX/test-suites.scm" <<'REG'
(suite "feature"    (kind log) (path "log-tests/feature-tests"))
(suite "regression" (kind log) (path "log-tests/regression-tests"))
REG

printf ']scheme-tests %s\n]suites feature regression\n]quit\n' "$FIX_NATIVE" \
  | $INTERP >/dev/null 2>&1

# Exactly one combined report for the whole ]suites batch (not one per suite).
nrun=$(ls -1 "$FIX/runs/"*.run 2>/dev/null | wc -l | tr -d '[:space:]')
if [ "$nrun" = 1 ]; then
  ok '.run: ]suites over two suites writes exactly one combined report'
else
  ng '.run: one combined report per ]suites' "expected 1 .run file in runs/, found $nrun"
fi

# Assert against the report's contents.
OUT="$(cat "$FIX/runs/"*.run 2>/dev/null)"
assert_contains '.run: combined report has the feature section'              'suite: feature'
assert_contains '.run: combined report has the regression section'           'suite: regression'
assert_contains '.run: failing case is recorded with its expression'         '(* 6 7)'
assert_contains '.run: failing case shows expected vs actual return'         'expected return: [999]'
assert_absent   '.run: passing feature case detail omitted (failure-only)'   '(+ 1 2)'
assert_absent   '.run: passing regression case detail omitted (failure-only)' '(list 1 2)'

rm -rf "$FIX"

# ---- summary ------------------------------------------------------------

printf '\ncli-tests: %d passed, %d failed  [%s]\n' "$pass" "$fail" "$INTERP"
[ "$fail" = 0 ]
