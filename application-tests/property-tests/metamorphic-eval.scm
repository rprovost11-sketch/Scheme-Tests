;;; metamorphic-eval.scm -- property-based evaluation-equivalence tester (Phase 4).
;;;
;;; Fifth metamorphic sibling, aimed at the evaluator/control core (the CEK machine).
;;; A deterministic generator builds random values and checks evaluation
;;; equivalences that must hold in any correct Scheme: let<->lambda, n-ary operator
;;; associativity, apply, multiple values, and and/or semantics. The equivalence is
;;; the oracle, so this catches evaluator bugs BOTH ports share. Values are pure
;;; (no side effects), so re-evaluating a subform is safe.
;;;
;;; Run:  python -m pyscheme metamorphic-eval.scm   (or the cppscheme2 exe)

(define seed 40503)
(define (rand!)
  (set! seed (modulo (+ (* seed 1103515245) 12345) 2147483648))
  seed)
(define (rand-below n) (modulo (rand!) n))
(define (gen-int) (* (if (= 0 (rand-below 2)) 1 -1) (rand-below 100000)))
(define (gen-val)                     ; a small assortment of self-evaluating-ish values
  (case (rand-below 4)
    ((0) (gen-int))
    ((1) (= 0 (rand-below 2)))
    ((2) (list (gen-int) (gen-int)))
    (else (gen-int))))

(define total 0)
(define fails 0)
(define (check name ok)
  (set! total (+ total 1))
  (if (not ok)
      (begin (set! fails (+ fails 1)) (display "FAIL: ") (write name) (newline))))

(define (laws a b c)
  ;; let <-> lambda
  (check (list 'let/lambda a b)
         (equal? (let ((x a)) (list x b)) ((lambda (x) (list x b)) a)))
  ;; let* <-> nested let
  (check (list 'let*/nest a b)
         (equal? (let* ((x a) (y (list x b))) y)
                 (let ((x a)) (let ((y (list x b))) y))))
  ;; n-ary + associativity (use ints)
  (let ((ia (if (integer? a) a 0)) (ib (if (integer? b) b 0)) (ic (if (integer? c) c 0)))
    (check (list '+assoc ia ib ic) (= (+ ia ib ic) (+ (+ ia ib) ic)))
    (check (list '*assoc ia ib ic) (= (* ia ib ic) (* ia (* ib ic))))
    (check (list 'apply+ ia ib ic) (= (apply + (list ia ib ic)) (+ ia ib ic))))
  ;; multiple values round-trip
  (check (list 'values a b)
         (equal? (call-with-values (lambda () (values a b)) list) (list a b)))
  ;; and / or reduce to if (only #f is false)
  (check (list 'and->if a b) (equal? (and a b) (if a b #f)))
  (check (list 'or->if  a b) (equal? (or a b)  (if a a b))))

(do ((i 0 (+ i 1))) ((= i 500))
  (laws (gen-val) (gen-val) (gen-val)))

(display total) (display " checks, ") (display fails) (display " failed") (newline)
