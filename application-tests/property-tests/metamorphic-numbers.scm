;;; metamorphic-numbers.scm -- property-based numeric tester (Phase 4 spearhead), SRFI 64.
;;;
;;; Generates random numbers with a DETERMINISTIC LCG (so failures reproduce) and
;;; asserts properties that must hold for ANY correct R7RS numeric tower. The
;;; PROPERTY is the oracle -- no reference implementation needed -- so this catches
;;; bugs that BOTH mirror ports share, which differential/fuzz testing cannot see.
;;; It directly probes the `rational`/bignum tower, the ~72%-on-both-ports coverage
;;; blind spot from Phase 1.
;;;
;;; Harness: SRFI 64 (run VIA the interpreter, cross-platform; needs -L <repo>/SRFI).
;;;
;;; KNOWN-OPEN (cppScheme2 only): the rational-LITERAL reader still uses int64, so
;;; (string->number "1/<bignum>") => #f even though the arithmetic and
;;; number->string sides are bignum-correct.  Rather than hard-code "cpp fails", we
;;; FEATURE-DETECT the bug once (`reader-handles-bignum-rational?`) and dynamically
;;; `test-expect-fail` exactly the roundtrips that would trip it.  So:
;;;   * pyScheme (reader correct)   -> detector true  -> nothing expect-failed -> clean pass.
;;;   * cppScheme2 (reader buggy)   -> detector false -> those roundtrips report XFAIL.
;;;   * when cppScheme2 is fixed    -> detector true  -> they pass clean automatically
;;;     (self-promoting; no port name baked in, no XPASS noise).
;;; A roundtrip failure NOT covered by the detector is a real, unexpected FAIL.
;;;
;;; Run:  python -m pyscheme -L <repo>/SRFI metamorphic-numbers.scm   (or cppscheme2)

(import (scheme base) (srfi 64))

;; ---- deterministic PRNG (LCG) ---------------------------------------------
(define seed 2463534242)
(define (rand!)
  (set! seed (modulo (+ (* seed 1103515245) 12345) 2147483648))
  seed)
(define (rand-below n) (modulo (rand!) n))              ; 0..n-1
(define (rand-sign)    (if (= 0 (rand-below 2)) 1 -1))

;; ---- generators ------------------------------------------------------------
(define (gen-small-int)  (* (rand-sign) (rand-below 1000)))
(define (gen-bignum)     (* (rand-sign) (expt (+ 2 (rand-below 36)) (+ 8 (rand-below 40)))))
(define (gen-int)        (if (= 0 (rand-below 2)) (gen-small-int) (gen-bignum)))
(define (gen-nonzero-int)(let ((n (gen-int))) (if (= n 0) 1 n)))
(define (gen-rational)   (/ (gen-int) (gen-nonzero-int)))   ; may reduce to an integer
(define (gen-real)       (let ((k (rand-below 3)))
                           (cond ((= k 0) (gen-int))
                                 ((= k 1) (gen-rational))
                                 (else    (inexact (gen-rational))))))

;; ---- known-open detector (cpp int64 rational-literal reader) ---------------
(define int64-limit (expt 2 63))                        ; first value past int64
(define reader-handles-bignum-rational?
  (and (string->number (string-append "1/" (number->string int64-limit))) #t))
;; A value trips the reader bug iff it's an exact non-integer rational whose
;; printed numerator or denominator lands at/over the int64 boundary.
(define (roundtrip-known-bad? x)
  (and (not reader-handles-bignum-rational?)
       (exact? x) (not (integer? x))
       (let ((n (abs (numerator x))) (d (denominator x)))
         (or (>= n int64-limit) (>= d int64-limit)))))

;; ---- properties (each must hold for a correct impl) ------------------------
(define (prop-roundtrip x)            ; write then read is identity
  (let ((name (list 'roundtrip x)))
    (when (roundtrip-known-bad? x) (test-expect-fail 1))   ; cpp known-open, next test
    (test-assert name
      (let ((y (string->number (number->string x))))
        (and y (= x y) (eqv? (exact? x) (exact? y)))))))

(define (prop-rational-normal x)      ; x = num/den, den>0, lowest terms
  (when (exact? x)
    (let ((n (numerator x)) (d (denominator x)))
      (test-assert (list 'rat-eq x) (= x (/ n d)))
      (test-assert (list 'rat-den+ x) (positive? d))
      (test-assert (list 'rat-lowest x) (= 1 (gcd (abs n) d))))))

(define (prop-negate x)               ; --x = x ; x + -x = 0
  (test-assert (list 'neg-neg x) (= x (- (- x))))
  (test-assert (list 'neg-sum x) (= 0 (+ x (- x)))))

(define (prop-add-comm a b) (test-assert (list 'add-comm a b) (= (+ a b) (+ b a))))
(define (prop-mul-comm a b) (test-assert (list 'mul-comm a b) (= (* a b) (* b a))))
(define (prop-distrib a b c)
  (test-assert (list 'distrib a b c) (= (* a (+ b c)) (+ (* a b) (* a c)))))

(define (prop-div-mod a b)            ; integers: a = q*b + r
  (when (and (integer? a) (integer? b) (exact? a) (exact? b) (not (= b 0)))
    (test-assert (list 'div-mod a b)
                 (= a (+ (* (quotient a b) b) (remainder a b))))))

(define (prop-abs-mul a b) (test-assert (list 'abs-mul a b) (= (abs (* a b)) (* (abs a) (abs b)))))

(define (prop-exact-inexact n)        ; small exact int survives the float trip
  (when (and (exact? n) (integer? n) (< (abs n) 1000000))
    (test-assert (list 'exact-inexact n) (= n (exact (inexact n))))))

;; ---- run -------------------------------------------------------------------
(test-begin "metamorphic-numbers")
(do ((i 0 (+ i 1))) ((= i 600))
  (let ((x (gen-real)) (a (gen-int)) (b (gen-nonzero-int)) (c (gen-int)))
    (prop-roundtrip x)
    (prop-rational-normal (gen-rational))
    (prop-negate x)
    (prop-add-comm a c)
    (prop-mul-comm a b)
    (prop-distrib a b c)
    (prop-div-mod a b)
    (prop-abs-mul a b)
    (prop-exact-inexact a)))
(test-end "metamorphic-numbers")
