;;; correctness-inprocess.scm -- shell-free ecraven correctness smoke.
;;;
;;; Replaces the bash correctness-sweep.sh for the common/quick path: instead of a
;;; shell concatenating files and spawning a process per benchmark, this loads each
;;; self-checking benchmark IN-PROCESS into a fresh isolated environment
;;; (make-environment) and reads back its own pass/fail.  It depends only on the
;;; interpreter -> runs on Windows / Linux / macOS with no shell.
;;;
;;; It is a PER-PORT correctness check: each benchmark validates its result against
;;; its own built-in ok? predicate (the canonical answer), so running this on cpp
;;; and on py independently covers correctness on both.  The explicit cpp-vs-py
;;; differential + full timed sweep (which need subprocess + timeout) stay in
;;; correctness-sweep.sh as a dev-tier meta-test pending the run-process primitive.
;;;
;;; NOTE: deliberately NOT SRFI 64.  SRFI 64 exports `test` as a MACRO, but several
;;; benchmarks (peval, simplex, ...) define `(define (test ...) ...)` as procedures;
;;; importing srfi 64 into the global env the benchmark child-envs inherit makes the
;;; macro shadow those procedures at expansion time (simplex then fails to expand).
;;; The benchmarks are self-checking, so a plain boolean tally is both sufficient
;;; and conflict-free.
;;;
;;; Run from the benchmark dir (the suite sets cwd) so relative aux inputs resolve:
;;;   cd <repo>/scheme-tests/application-tests/ecraven-r7rs-benchmarks
;;;   <interp> correctness-inprocess.scm

(import (scheme base) (scheme file) (scheme eval) (scheme write))

;; QUICK subset: benchmarks that finish fast on BOTH ports with the thunk run ONCE
;; (correctness mode).  Mirrors correctness-sweep.sh's QUICK_BENCHES.  Heavy
;; benchmarks (tak/nboyer/earley/...) are excluded -- a tree-walker can't finish
;; them quickly and there is no in-process timeout; the full sweep covers them.
(define quick-benches
  '("browse" "chudnovsky" "deriv" "destruc" "diviter" "divrec" "dynamic"
    "matrix" "maze" "mazefun" "peval" "pi" "pnpoly" "primes" "quicksort"
    "read1" "scheme" "simplex" "slatex" "string" "sum" "tail"))

;; Correctness shim: replace common.scm's timing run-r7rs-benchmark with one that
;; runs the thunk ONCE and records pass/fail in the benchmark's own fresh env.
;; (run-benchmark resolves run-r7rs-benchmark at call time, after this redefinition.)
(define shim
  '(begin
     (define %bench-ran #f)
     (define %bench-ok #f)
     (define (run-r7rs-benchmark name count thunk ok?)
       (set! %bench-ran #t)
       (set! %bench-ok (and (ok? (thunk)) #t)))))

;; Run one benchmark in a fresh isolated env; suppress its output to a sink port.
;; Any error (crash, missing aux file, ...) is caught -> #f (a failure).
(define (bench-ok? bench)
  (let ((env (make-environment))
        (sink (open-output-string)))
    (guard (e (#t #f))
      (parameterize ((current-output-port sink))
        (with-input-from-file (string-append "inputs/" bench ".input")
          (lambda ()
            (load (string-append "src/" bench ".scm") env)
            (load "src/common.scm" env)
            (eval shim env)
            (eval '(run-benchmark) env))))
      (and (eval '%bench-ran env) (eval '%bench-ok env) #t))))

(define total 0)
(define fails 0)
(for-each
 (lambda (b)
   (set! total (+ total 1))
   (let ((ok (bench-ok? b)))
     (unless ok (set! fails (+ fails 1)))
     (display (if ok "ok   " "FAIL ")) (display b) (newline)))
 quick-benches)
(display "=== ") (display (- total fails)) (display " passed, ")
(display fails) (display " failed ===") (newline)
(exit (if (= fails 0) 0 1))
