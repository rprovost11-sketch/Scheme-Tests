;;; known-open-bugs.scm -- SRFI-64 pins for parked BOTH-PORTS known-open bugs.
;;;
;;; Each parked bug is wrapped in `test-expect-fail` so it reports XFAIL (an
;;; expected failure that does NOT fail the run) until fixed; when fixed the
;;; round-trip passes and the harness reports XPASS -- the cue to remove the pin
;;; and promote it to a regression test.  Runs identically on both ports.
;;;
;;; CURRENT STATUS: no both-ports known-open bugs are pinned right now.  The two
;;; that lived here -- complex inf/nan write doubling, and symbol bar-quoting of
;;; @ / .9t -- were fixed 2026-06-19 and promoted to
;;; log-tests/regression-tests/02-printer.log.  Only a sanity round-trip remains;
;;; add a (test-expect-fail ...) + (test-assert ...) pair here when the next
;;; both-ports bug is parked.  (The remaining known-open bugs are cppScheme2-only:
;;; the bignum-rational literal reader -- feature-detected in metamorphic-numbers
;;; -- and the ecraven earley crash.)
;;;
;;; Run (note the -L so (srfi 64) resolves):
;;;   <interp> -L <repo>/SRFI known-open-bugs.scm

(import (scheme base) (scheme write) (scheme read) (srfi 64))

(define (write/read-equal? x)
  (let ((p (open-output-string)))
    (write x p)
    (equal? (read (open-input-string (get-output-string p))) x)))

(test-begin "known-open-bugs")
;; sanity round-trip (also keeps the SRFI-64 harness exercised on both ports).
(test-assert "roundtrip-plain-datum" (write/read-equal? '(1 2 "three" #\x)))
(test-end "known-open-bugs")
