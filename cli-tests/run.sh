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

# ---- summary ------------------------------------------------------------

printf '\ncli-tests: %d passed, %d failed  [%s]\n' "$pass" "$fail" "$INTERP"
[ "$fail" = 0 ]
