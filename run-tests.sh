#!/bin/sh
# run-tests.sh -- manifest-driven test orchestrator (backlog #9, single source of
# truth = tests.manifest beside this script). The REPL (]suites) and Cherry delegate
# here, so the manifest is the ONE place a test is registered.
#
#   bash run-tests.sh                  run every test
#   bash run-tests.sh all              run every test
#   bash run-tests.sh <name>...        run the named test(s)
#   bash run-tests.sh --list           print test names, one per line (for UIs)
#   bash run-tests.sh --list-detail    print  name<TAB>kind<TAB>ports  (for UIs)
#
# Known-open bugs (the manifest's xfail column) are reported as "xfail" and do not
# fail the run; a known-open test that PASSES is flagged "FIXED!"; only an
# unexpected failure makes the run exit nonzero.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LISP="$(dirname "$HERE")"
TESTS="$HERE"
SRFI="$LISP/SRFI"
PYDIR="$LISP/3PyScheme"
CPPEXE="$LISP/4CPPScheme2/build/Release/cppscheme2.exe"
MANIFEST="$HERE/tests.manifest"

# emit the data rows of the manifest (strip comments/blanks)
rows() { grep -vE '^[[:space:]]*(#|$)' "$MANIFEST"; }

# ---- discovery modes -------------------------------------------------------
case "${1:-}" in
  --list)        rows | cut -d'|' -f1; exit 0;;
  --list-detail) rows | awk -F'|' '{printf "%s\t%s\t%s\n",$1,$2,$3}'; exit 0;;
esac

# ---- selection -------------------------------------------------------------
SELECT="$*"; [ -z "$SELECT" ] && SELECT="all"; [ "$SELECT" = "all" ] && SELECT=""
selected() { [ -z "$SELECT" ] && return 0; case " $SELECT " in *" $1 "*) return 0;; *) return 1;; esac; }

[ -x "$CPPEXE" ] || { echo "ERROR: no cppScheme2 Release build at $CPPEXE." >&2; exit 2; }

pass=0; fail=0; xfail=0; fixed=0
# record <name> <port> <ok 0/1> <xfail-list>
record() {
  n="$1"; p="$2"; ok="$3"; xf="$4"
  case ",$xf," in *",$p,"*) known=1;; *) known=0;; esac
  if [ "$known" -eq 1 ]; then
    if [ "$ok" -eq 0 ]; then printf '  xfail  %-24s %-4s (known-open)\n' "$n" "$p"; xfail=$((xfail+1))
    else printf '  FIXED! %-24s %-4s (was known-open -- promote it)\n' "$n" "$p"; fixed=$((fixed+1)); fi
  else
    if [ "$ok" -eq 1 ]; then printf '  ok     %-24s %s\n' "$n" "$p"; pass=$((pass+1))
    else printf '  FAIL   %-24s %s\n' "$n" "$p"; fail=$((fail+1)); fi
  fi
}
ok_if_grep() { echo "$1" | grep -qE "$2" && echo 1 || echo 0; }

# ports a test applies to, intersected with what's runnable
ports_of() { case "$1" in py) echo py;; cpp) echo cpp;; both) echo "py cpp";; esac; }

run_one() {
  name="$1"; kind="$2"; ports="$3"; arg="$4"; xf="$5"
  case "$kind" in
    battery)
      for p in $(ports_of "$ports"); do
        if [ "$p" = py ]; then out="$(printf ']suites all\n' | { PYTHONPATH="$PYDIR" python -m pyscheme -T "$TESTS" -L "$SRFI"; } 2>&1)"
        else out="$(printf ']suites all\n' | "$CPPEXE" -T "$TESTS" -L "$SRFI" 2>&1)"; fi
        record "$name" "$p" "$(ok_if_grep "$out" 'ALL SUITES PASSED')" "$xf"
      done;;
    cli)
      for p in $(ports_of "$ports"); do
        if [ "$p" = py ]; then out="$(PYTHONPATH="$PYDIR" sh "$TESTS/cli-tests/run.sh" 'python -m pyscheme' 2>&1)"
        else out="$(sh "$TESTS/cli-tests/run.sh" "$CPPEXE" 2>&1)"; fi
        record "$name" "$p" "$(ok_if_grep "$out" '0 failed')" "$xf"
      done;;
    pytool)   # python harness in cross-port-tests/, drives both ports itself
      if ( cd "$TESTS/cross-port-tests" && python $arg ) >/dev/null 2>&1; then record "$name" both 1 "$xf"; else record "$name" both 0 "$xf"; fi;;
    scheme)
      for p in $(ports_of "$ports"); do
        if [ "$p" = py ]; then out="$(PYTHONPATH="$PYDIR" python -m pyscheme "$TESTS/$arg" 2>&1)"
        else out="$("$CPPEXE" "$TESTS/$arg" 2>&1)"; fi
        record "$name" "$p" "$(ok_if_grep "$out" '0 failed')" "$xf"
      done;;
    exe)
      for p in $(ports_of "$ports"); do
        if "$LISP/$arg" >/dev/null 2>&1; then record "$name" "$p" 1 "$xf"; else record "$name" "$p" 0 "$xf"; fi
      done;;
    *) echo "  ?? unknown kind '$kind' for $name" >&2;;
  esac
}

echo "================ TEST ARSENAL (run-tests.sh) ================"
rows | while IFS='|' read -r name kind ports arg xf; do
  selected "$name" || continue
  echo "-- $name ($kind) --"
  run_one "$name" "$kind" "$ports" "$arg" "$xf"
done > /tmp/run-tests.$$ 2>&1
# (the while-loop ran in a subshell via the pipe; re-tally from its output)
cat /tmp/run-tests.$$
pass=$(grep -c '^  ok '    /tmp/run-tests.$$ || true)
fail=$(grep -c '^  FAIL '  /tmp/run-tests.$$ || true)
xfail=$(grep -c '^  xfail ' /tmp/run-tests.$$ || true)
fixed=$(grep -c '^  FIXED' /tmp/run-tests.$$ || true)
rm -f /tmp/run-tests.$$

echo
echo "================ SUMMARY ================"
printf '  %s passed, %s failed, %s xfail (known-open), %s FIXED\n' "$pass" "$fail" "$xfail" "$fixed"
[ "$fail" -gt 0 ] && { echo "  -> UNEXPECTED FAILURES."; exit 1; }
[ "$fixed" -gt 0 ] && echo "  -> a known-open test now passes; update tests.manifest's xfail column."
echo "  -> all non-known-open selected tests pass."
exit 0
