#!/bin/sh
# run-all-tests.sh -- run the ENTIRE test arsenal on both ports and print one
# pass/fail summary. The point: anyone (you or me) runs ONE command to exercise
# every test, so neither of us has a test the other can't run.
#
#   bash run-all-tests.sh            # the fast+core arsenal (~2-3 min)
#   bash run-all-tests.sh --slow     # also the ecraven correctness sweep (long)
#
# KNOWN-OPEN bugs are expected to fail (see KNOWN_OPEN below); they are reported
# as "xfail" (expected) and do NOT fail the run. A KNOWN-OPEN test that suddenly
# PASSES is flagged "FIXED!" (someone fixed the bug -> promote the test). Only an
# unexpected failure makes the run exit nonzero.
#
# Layout assumed: this repo (scheme-tests) sits beside 3PyScheme and 4CPPScheme2.
# Requires: python on PATH (pyScheme is stdlib-only) and a cppScheme2 Release build.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LISP="$(dirname "$HERE")"
TESTS="$HERE"
SRFI="$LISP/SRFI"
PYDIR="$LISP/3PyScheme"
CPPEXE="$LISP/4CPPScheme2/build/Release/cppscheme2.exe"
PY="PYTHONPATH=$PYDIR python -m pyscheme"

pass=0; fail=0; xfail=0; fixed=0
# "name|port" entries that are expected to fail until their bug is fixed:
KNOWN_OPEN=" metamorphic-numbers|cpp metamorphic-datums|py metamorphic-datums|cpp "

is_known_open() { case "$KNOWN_OPEN" in *" $1|$2 "*) return 0;; *) return 1;; esac; }

# record <name> <port> <ok?0/1>
record() {
  name="$1"; port="$2"; ok="$3"
  if is_known_open "$name" "$port"; then
    if [ "$ok" -eq 0 ]; then printf '  xfail  %-26s %-3s (known-open bug)\n' "$name" "$port"; xfail=$((xfail+1))
    else printf '  FIXED! %-26s %-3s (was known-open -- promote it)\n' "$name" "$port"; fixed=$((fixed+1)); fi
  else
    if [ "$ok" -eq 1 ]; then printf '  ok     %-26s %s\n' "$name" "$port"; pass=$((pass+1))
    else printf '  FAIL   %-26s %s\n' "$name" "$port"; fail=$((fail+1)); fi
  fi
}

# run_pat <name> <port> <success-grep-pattern> <command...>
run_pat() {
  name="$1"; port="$2"; pat="$3"; shift 3
  out="$(eval "$@" 2>&1)"
  if echo "$out" | grep -qE "$pat"; then record "$name" "$port" 1; else record "$name" "$port" 0; fi
}
# run_rc <name> <port> <command...>  -- pass iff exit 0
run_rc() { name="$1"; port="$2"; shift 2; if eval "$@" >/dev/null 2>&1; then record "$name" "$port" 1; else record "$name" "$port" 0; fi; }

[ -x "$CPPEXE" ] || { echo "ERROR: no cppScheme2 Release build at $CPPEXE -- build it first." >&2; exit 2; }

echo "================ TEST ARSENAL ================"
echo "  pyScheme  : $PY"
echo "  cppScheme2: $CPPEXE"
echo "  tests dir : $TESTS"
echo

echo "-- gated battery (feature + compliance + regression) --"
run_pat battery py  'ALL SUITES PASSED' "printf ']suites all\n' | $PY -T '$TESTS' -L '$SRFI'"
run_pat battery cpp 'ALL SUITES PASSED' "printf ']suites all\n' | '$CPPEXE' -T '$TESTS' -L '$SRFI'"

echo "-- cli / process-boundary tests --"
run_pat cli-tests py  '0 failed' "PYTHONPATH='$PYDIR' sh '$TESTS/cli-tests/run.sh' 'python -m pyscheme'"
run_pat cli-tests cpp '0 failed' "sh '$TESTS/cli-tests/run.sh' '$CPPEXE'"

echo "-- cross-port differential + fuzz (cpp vs py) --"
run_rc  cross-port both "cd '$TESTS/cross-port-tests' && python diff.py"
run_rc  fuzz-smoke both "cd '$TESTS/cross-port-tests' && python fuzz.py --n 30 --seed 1"

echo "-- metamorphic property tests --"
for m in metamorphic-numbers metamorphic-datums metamorphic-compare metamorphic-strings metamorphic-eval; do
  f="$TESTS/application-tests/property-tests/$m.scm"
  run_pat "$m" py  '0 failed' "$PY '$f'"
  run_pat "$m" cpp '0 failed' "'$CPPEXE' '$f'"
done

echo "-- white-box GC (cppScheme2) --"
run_rc  gc_test cpp "'$LISP/4CPPScheme2/build/Release/gc_test.exe'"

if [ "${1:-}" = "--slow" ]; then
  echo "-- ecraven correctness sweep (long) --"
  run_rc ecraven-sweep both "cd '$TESTS/application-tests/ecraven-r7rs-benchmarks' && bash correctness-sweep.sh 60"
fi

echo
echo "================ SUMMARY ================"
printf '  %d passed, %d failed, %d xfail (known-open), %d FIXED\n' "$pass" "$fail" "$xfail" "$fixed"
if [ "$fail" -gt 0 ]; then echo "  -> UNEXPECTED FAILURES present."; exit 1; fi
if [ "$fixed" -gt 0 ]; then echo "  -> a known-open test now passes; promote it out of KNOWN_OPEN."; fi
echo "  -> all non-known-open tests pass."
exit 0
