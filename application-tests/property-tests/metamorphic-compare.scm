;;; metamorphic-compare.scm -- property-based ordering tester (Phase 4).
;;;
;;; Third metamorphic sibling, aimed at the comparison operators (Phase 1 flagged
;;; `comparison` sub-90% on both ports). A deterministic generator builds random
;;; reals across the tower -- small ints, bignums, rationals (incl. bignum
;;; num/denom), and inexacts -- and asserts the laws every total order must obey.
;;; The laws are the oracle, so this catches comparison bugs BOTH ports share,
;;; especially in mixed exact/inexact and bignum-vs-inexact comparisons.
;;; NaN is excluded (it is unordered by design).
;;;
;;; Run:  python -m pyscheme metamorphic-compare.scm   (or the cppscheme2 exe)

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

(define total 0)
(define fails 0)
(define (check name ok)
  (set! total (+ total 1))
  (if (not ok)
      (begin (set! fails (+ fails 1)) (display "FAIL: ") (write name) (newline))))

(define (one-of a b c) (= 1 (+ (if a 1 0) (if b 1 0) (if c 1 0))))

(define (laws a b)
  (check (list 'trichotomy a b) (one-of (< a b) (= a b) (> a b)))
  (check (list 'flip a b)       (eq? (< a b) (> b a)))
  (check (list 'le-def a b)     (eq? (<= a b) (not (> a b))))
  (check (list 'ge-def a b)     (eq? (>= a b) (not (< a b))))
  (check (list 'eq-le-ge a b)   (eq? (= a b) (and (<= a b) (>= a b))))
  (check (list 'min a b)        (= (min a b) (if (<= a b) a b)))
  (check (list 'max a b)        (= (max a b) (if (>= a b) a b))))

(define (transitivity a b c)             ; if a<=b and b<=c then a<=c
  (if (and (<= a b) (<= b c))
      (check (list 'trans a b c) (<= a c))))

(do ((i 0 (+ i 1))) ((= i 600))
  (let ((a (gen-real)) (b (gen-real)) (c (gen-real)))
    (laws a b)
    (laws a a)                            ; reflexive / equal-to-self edge
    (transitivity a b c)))

(display total) (display " checks, ") (display fails) (display " failed") (newline)
