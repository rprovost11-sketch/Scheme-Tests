;;; known-open-bugs.scm -- SRFI 64 pins for the parked known-open bugs.
;;;
;;; Each known-open bug is wrapped in `test-expect-fail`, so TODAY it reports
;;; XFAIL (an expected failure, which does NOT fail the run).  When a bug is
;;; fixed the round-trip starts passing and the harness reports XPASS -- the
;;; signal to remove the pin (the SRFI-64 analogue of the orchestrator's
;;; "FIXED!").  These are the BOTH-PORTS bugs, so the file runs identically on
;;; pyScheme and cppScheme2.  Source of the bug list: scheme-tests/TESTING.md.
;;;
;;; This file is also the proof-of-concept for `test-expect-fail`: a normal pass
;;; (sanity) sits alongside three pinned failures, and the summary distinguishes
;;; them (X passed / 0 failed / 3 expected-fail).
;;;
;;; Run (note the -L so (srfi 64) resolves):
;;;   python -m pyscheme -L <repo>/SRFI known-open-bugs.scm
;;;   cppscheme2          -L <repo>/SRFI known-open-bugs.scm

(import (scheme base) (scheme write) (scheme read) (scheme complex) (srfi 64))

;; write x to a string, read it back, return #t iff it re-reads equal?.  Any
;; error during read (e.g. an un-bar-quoted symbol) counts as a failure.
(define (write/read-equal? x)
  (let ((p (open-output-string)))
    (write x p)
    (equal? (read (open-input-string (get-output-string p))) x)))

(test-begin "known-open-bugs")

;; sanity: a writer round-trip that DOES work, so pass-count is nonzero and the
;; expected-fails below are clearly distinguished from a blanket failure.
(test-assert "roundtrip-plain-datum" (write/read-equal? '(1 2 "three" #\x)))

;; KNOWN-OPEN 1 -- complex inf/nan write doubles the sign:
;;   (number->string (make-rectangular 3.0 +inf.0)) => "3.0++inf.0i"  (not re-readable)
(test-expect-fail "complex-inf-write-roundtrip")
(test-assert "complex-inf-write-roundtrip"
  (let ((z (string->number (number->string (make-rectangular 3.0 +inf.0)))))
    (and z (= (real-part z) 3.0) (= (imag-part z) +inf.0))))

;; KNOWN-OPEN 3 -- write doesn't bar-quote symbols that need it; they write bare
;; and don't re-read (read raises).
(test-expect-fail "symbol-@-write-roundtrip")
(test-assert "symbol-@-write-roundtrip" (write/read-equal? (string->symbol "@")))

(test-expect-fail "symbol-.9t-write-roundtrip")
(test-assert "symbol-.9t-write-roundtrip" (write/read-equal? (string->symbol ".9t")))

(test-end "known-open-bugs")
