#!/usr/bin/env bash
#
# correctness-sweep.sh -- a lightweight, unattended-safe CORRECTNESS pass over
# the ecraven r7rs-benchmarks for the two ports (pyScheme + cppScheme2).
#
# Unlike `./bench` (which measures TIMING via a full protocol and relies on
# `ulimit -t`, not enforced under Windows git-bash so slow benchmarks hang),
# this runs each benchmark ONCE per port under a real GNU `timeout`, captures
# the benchmark's self-reported result, and classifies it:
#
#   OK        -- ran, self-check passed  (+!CSVLINE!+...,<seconds>)
#   INCORRECT -- ran, self-check failed  (+!CSVLINE!+...,INCORRECT)
#   CRASH     -- nonzero exit, no result line
#   TIMEOUT   -- exceeded the per-benchmark limit
#
# The #5 signal is a cpp-vs-py CORRECTNESS divergence: one port OK while the
# other is INCORRECT or CRASH.  TIMEOUT on a side is INCONCLUSIVE (a speed
# difference in a tree-walker, not a correctness bug) and is reported apart.
#
# Usage:  bash correctness-sweep.sh [quick | timeout_seconds] [benchmark ...]
#   quick            a short timeout over a curated FAST subset -- a seconds-scale
#                    smoke (skips the heavy benchmarks that only ever time out in
#                    a tree-walker, so there's no timeout padding).
#   timeout_seconds  full sweep over every benchmark at that per-benchmark GNU
#                    `timeout` (default 30).
#   benchmark ...    restrict the sweep to the named benchmarks (overrides the
#                    quick subset / the full list).
#
# Builds match `bench`'s make_src_code:
#   <impl>-prelude? + <name>.scm + common.scm + <impl>-postlude + common-postlude

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# Run from the benchmark dir so benchmarks that open auxiliary data by RELATIVE
# path (cat->inputs/bib, dynamic->inputs/dynamic.data, ...) resolve for BOTH
# ports identically.  pyScheme is run via PYTHONPATH (no cd) so it keeps this cwd.
cd "$HERE"
SRC="$HERE/src"
INPUTS="$HERE/inputs"
LISP_ROOT="$(cd "$HERE/../../.." && pwd)"

CPPSCHEME2="${CPPSCHEME2:-$LISP_ROOT/4CPPScheme2/build/Release/cppscheme2.exe}"
PYSCHEME_DIR="${PYSCHEME_DIR:-$LISP_ROOT/3PyScheme}"

# QUICK_BENCHES: the benchmarks that complete fast on BOTH ports in correctness
# mode (run the thunk once) -- i.e. the agree-OK set, empirically derived.  The
# quick smoke runs only these, so it never pays a timeout for a heavy benchmark
# that a tree-walker can't finish.  If a benchmark is added it simply won't be in
# the quick smoke until added here; correctness is unaffected (the full sweep
# still covers everything).
QUICK_BENCHES="browse chudnovsky deriv destruc diviter divrec dynamic matrix maze mazefun peval pi pnpoly primes quicksort read1 scheme simplex slatex string sum tail"

QUICK=0
if [ "${1:-}" = "quick" ]; then
  QUICK=1
  TIMELIMIT=10
  shift
else
  TIMELIMIT="${1:-30}"
  if [ "$#" -ge 1 ]; then shift; fi
fi
SELECT="$*"   # any remaining args = an explicit benchmark list

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Correctness-mode shim: override run-r7rs-benchmark to run the thunk ONCE
# (ignoring the input's timing iteration count, which is tuned for compiled
# Schemes and would make a tree-walker time out) and report only pass/fail.
# Injected AFTER the impl postlude (so this-scheme-implementation-name exists)
# and BEFORE common-postlude.scm (which calls (run-benchmark)).
SHIM="$TMP/correctness-mode.scm"
cat > "$SHIM" <<'SCM'
(define (run-r7rs-benchmark name count thunk ok?)
  (let ((result (thunk)))
    (if (ok? result)
        (begin (display "+!CSVLINE!+") (display (this-scheme-implementation-name))
               (display ",") (display name) (display ",OK") (newline))
        (begin (display "ERROR: returned incorrect result: ") (write result) (newline)
               (display "+!CSVLINE!+") (display (this-scheme-implementation-name))
               (display ",") (display name) (display ",INCORRECT") (newline)))
    (flush-output-port (current-output-port))))
SCM

# build <impl-NAME> <benchmark> -> writes $TMP/<benchmark>.<impl>.scm, echoes path
build () {
  local name="$1" bench="$2"
  local pre="$SRC/$name-prelude.scm"; [ -e "$pre" ] || pre=/dev/null
  local post="$SRC/$name-postlude.scm"; [ -e "$post" ] || post=/dev/null
  local out="$TMP/$bench.$name.scm"
  cat "$pre" "$SRC/$bench.scm" "$SRC/common.scm" "$post" "$SHIM" "$SRC/common-postlude.scm" > "$out"
  printf '%s' "$out"
}

# classify <output-text> <rc> -> one of OK INCORRECT CRASH TIMEOUT NORESULT
classify () {
  local out="$1" rc="$2"
  if [ "$rc" = 124 ]; then echo TIMEOUT; return; fi
  case "$out" in
    *",INCORRECT"*) echo INCORRECT; return ;;
    *",OK"*) echo OK; return ;;
  esac
  if printf '%s' "$out" | grep -qE '\+!CSVLINE!\+[^,]*,[^,]*,[0-9]'; then echo OK; return; fi
  if [ "$rc" != 0 ]; then echo CRASH; return; fi
  echo NORESULT
}

if [ -n "$SELECT" ]; then
  benches="$SELECT"
elif [ "$QUICK" = 1 ]; then
  benches="$QUICK_BENCHES"
else
  benches="$(ls "$INPUTS"/*.input 2>/dev/null | xargs -n1 basename | sed 's/\.input//' | sort)"
fi
printf 'correctness sweep  (%s, timeout=%ss/benchmark)\n  cpp: %s\n  py : python -m pyscheme @ %s\n\n' \
  "$([ "$QUICK" = 1 ] && echo 'quick subset' || echo 'full')" \
  "$TIMELIMIT" "$CPPSCHEME2" "$PYSCHEME_DIR"
printf '%-14s %-10s %-10s %s\n' BENCHMARK CPP PY NOTE

diverge=0; agree=0; inconclusive=0
for b in $benches; do
  [ -e "$SRC/$b.scm" ] || continue
  cf="$(build CPPScheme2 "$b")"
  pf="$(build PyScheme "$b")"
  co="$(timeout "$TIMELIMIT" "$CPPSCHEME2" "$cf" < "$INPUTS/$b.input" 2>&1)"; crc=$?
  po="$(PYTHONPATH="$PYSCHEME_DIR" timeout "$TIMELIMIT" python -m pyscheme "$pf" < "$INPUTS/$b.input" 2>&1)"; prc=$?
  cc="$(classify "$co" "$crc")"
  pc="$(classify "$po" "$prc")"
  note=""
  if [ "$cc" = TIMEOUT ] || [ "$pc" = TIMEOUT ] || [ "$cc" = NORESULT ] || [ "$pc" = NORESULT ]; then
    note="inconclusive"; inconclusive=$((inconclusive+1))
  elif [ "$cc" = "$pc" ]; then
    [ "$cc" = OK ] && agree=$((agree+1)) || note="both $cc"
  else
    note="*** DIVERGENCE ***"; diverge=$((diverge+1))
  fi
  printf '%-14s %-10s %-10s %s\n' "$b" "$cc" "$pc" "$note"
done

printf '\nsummary: %d agree-OK, %d DIVERGENCE, %d inconclusive(timeout/noresult)\n' \
  "$agree" "$diverge" "$inconclusive"
[ "$diverge" = 0 ]
