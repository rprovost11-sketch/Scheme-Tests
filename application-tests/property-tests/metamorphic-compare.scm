;;; metamorphic-compare.scm -- property-based ordering tester (Phase 4), SRFI 64.
;;;
;;; Third metamorphic sibling, aimed at the comparison operators (Phase 1 flagged
;;; `comparison` sub-90% on both ports). A deterministic generator builds random
;;; reals across the tower -- small ints, bignums, rationals (incl. bignum
;;; num/denom), and inexacts -- and asserts the laws every total order must obey.
;;; The laws are the oracle, so this catches comparison bugs BOTH ports share,
;;; especially in mixed exact/inexact and bignum-vs-inexact comparisons.
;;; NaN is excluded (it is unordered by design).
;;;
;;; Harness: SRFI 64 (the standard Scheme test harness) -- this is the proof-of-
;;; concept for running the property suites VIA THE INTERPRETER, cross-platform,
;;; with no external shell/Python.  Each law is a boolean predicate, so it maps to
;;; `test-assert`; the min/max laws stay `test-assert` over `=` (numeric equality)
;;; rather than `test-equal`, because min/max exactness-contagion can yield an
;;; inexact result against an exact operand -- which `=` accepts but the harness's
;;; (exactness-aware) equality would reject.
;;;
;;; Run (note the -L so (srfi 64) resolves):
;;;   python -m pyscheme -L <repo>/SRFI metamorphic-compare.scm
;;;   cppscheme2          -L <repo>/SRFI metamorphic-compare.scm

(import (scheme base) (srfi 64))

(define seed 1779033703)
(define (rand!)
  (set! seed (modulo (+ (* seed 1103515245) 12345) 2147483648))
  seed)
(define (rand-below n) (modulo (rand!) n))
(define (rand-sign) (if (= 0 (rand-below 2)) 1 -1))

(define (gen-int)
  (if (= 0 (rand-below 2))
      (* (rand-sign) (rand-below 1000))
      (* (rand-sign) (expt (+ 2 (rand-below 12)) (+ 8 (rand-below 30))))))
(define (gen-real)
  (case (rand-below 4)
    ((0) (gen-int))
    ((1) (/ (gen-int) (let ((d (gen-int))) (if (= d 0) 1 d))))   ; rational
    ((2) (inexact (/ (gen-int) (+ 1 (rand-below 100)))))         ; inexact
    (else (* (rand-sign) (inexact (rand-below 100000))))))

(define (one-of a b c) (= 1 (+ (if a 1 0) (if b 1 0) (if c 1 0))))

(define (laws a b)
  (test-assert (list 'trichotomy a b) (one-of (< a b) (= a b) (> a b)))
  (test-assert (list 'flip a b)       (eq? (< a b) (> b a)))
  (test-assert (list 'le-def a b)     (eq? (<= a b) (not (> a b))))
  (test-assert (list 'ge-def a b)     (eq? (>= a b) (not (< a b))))
  (test-assert (list 'eq-le-ge a b)   (eq? (= a b) (and (<= a b) (>= a b))))
  (test-assert (list 'min a b)        (= (min a b) (if (<= a b) a b)))
  (test-assert (list 'max a b)        (= (max a b) (if (>= a b) a b))))

(define (transitivity a b c)             ; if a<=b and b<=c then a<=c
  (if (and (<= a b) (<= b c))
      (test-assert (list 'trans a b c) (<= a c))))

(test-begin "metamorphic-compare")
(do ((i 0 (+ i 1))) ((= i 600))
  (let ((a (gen-real)) (b (gen-real)) (c (gen-real)))
    (laws a b)
    (laws a a)                            ; reflexive / equal-to-self edge
    (transitivity a b c)))
(test-end "metamorphic-compare")
