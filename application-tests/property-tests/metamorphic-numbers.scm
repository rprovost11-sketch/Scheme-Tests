;;; metamorphic-numbers.scm -- property-based numeric tester (Phase 4 spearhead).
;;;
;;; Generates random numbers with a DETERMINISTIC LCG (so failures reproduce) and
;;; asserts properties that must hold for ANY correct R7RS numeric tower. The
;;; PROPERTY is the oracle -- no reference implementation needed -- so this catches
;;; bugs that BOTH mirror ports share, which differential/fuzz testing cannot see.
;;; It directly probes the `rational`/bignum tower, the ~72%-on-both-ports coverage
;;; blind spot from Phase 1.
;;;
;;; Self-checking: prints "<N> checks, <F> failed"; each failure prints its case.
;;; Run:  python -m pyscheme metamorphic-numbers.scm   (or the cppscheme2 exe)
;;; Deliberately avoids complex inf/nan (a KNOWN-OPEN write bug) so a clean port
;;; passes; everything else in the tower is fair game.
;;;
;;; CURRENT RESULTS (2026-06-18):
;;;   pyScheme   -- 6606 checks, 0 failed  (properties validated against the
;;;                 reference-correct port).
;;;   cppScheme2 -- 6606 checks, 164 failed, ALL `roundtrip`.  This surfaced a
;;;                 NEW, real, cpp-only bug: the rational-LITERAL reader still uses
;;;                 int64, so (string->number "1/<bignum>") => #f even though the
;;;                 arithmetic and number->string sides are bignum-correct.  Found
;;;                 in the rational tower -- the Phase-1 shared-coverage blind spot.
;;;                 KNOWN-OPEN (not fixed, per the freeze).  When fixed, cppScheme2
;;;                 will pass clean and this can be promoted into the gated suite.

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

;; ---- harness ---------------------------------------------------------------
(define total 0)
(define fails 0)
(define (check name ok)
  (set! total (+ total 1))
  (if (not ok)
      (begin (set! fails (+ fails 1))
             (display "FAIL: ") (write name) (newline))))

;; ---- properties (each must hold for a correct impl) ------------------------
(define (prop-roundtrip x)            ; write then read is identity
  (check (list 'roundtrip x)
         (let ((y (string->number (number->string x))))
           (and y (= x y) (eqv? (exact? x) (exact? y))))))

(define (prop-rational-normal x)      ; x = num/den, den>0, lowest terms
  (if (exact? x)
      (let ((n (numerator x)) (d (denominator x)))
        (check (list 'rat-eq x) (= x (/ n d)))
        (check (list 'rat-den+ x) (positive? d))
        (check (list 'rat-lowest x) (= 1 (gcd (abs n) d))))))

(define (prop-negate x)               ; --x = x ; x + -x = 0
  (check (list 'neg-neg x) (= x (- (- x))))
  (check (list 'neg-sum x) (= 0 (+ x (- x)))))

(define (prop-add-comm a b) (check (list 'add-comm a b) (= (+ a b) (+ b a))))
(define (prop-mul-comm a b) (check (list 'mul-comm a b) (= (* a b) (* b a))))
(define (prop-distrib a b c)
  (check (list 'distrib a b c) (= (* a (+ b c)) (+ (* a b) (* a c)))))

(define (prop-div-mod a b)            ; integers: a = q*b + r
  (if (and (integer? a) (integer? b) (exact? a) (exact? b) (not (= b 0)))
      (check (list 'div-mod a b)
             (= a (+ (* (quotient a b) b) (remainder a b))))))

(define (prop-abs-mul a b) (check (list 'abs-mul a b) (= (abs (* a b)) (* (abs a) (abs b)))))

(define (prop-exact-inexact n)        ; small exact int survives the float trip
  (if (and (exact? n) (integer? n) (< (abs n) 1000000))
      (check (list 'exact-inexact n) (= n (exact (inexact n))))))

;; ---- run -------------------------------------------------------------------
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

(display total) (display " checks, ") (display fails) (display " failed") (newline)
