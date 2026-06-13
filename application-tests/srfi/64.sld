;; Minimal portable (srfi 64) -- a partial SRFI-64 test harness plus chibi
;; (chibi test)'s `(test expected expr)` form, enough to run chibi's
;; r7rs-tests.scm on pyscheme / cppscheme2.  Written in portable R7RS so the
;; SAME file is loaded identically by both ports (parity by construction).
;;
;; Reporting: each failure prints one "FAIL ..." line; the outermost test-end
;; prints "=== P passed, F failed ===".  This is a deliberately small subset
;; (not the full SRFI-64 runner object model).
(define-library (srfi 64)
  (export test test-equal test-eqv test-assert test-error test-values
          test-begin test-end test-group test-runner-fail-count)
  (import (scheme base) (scheme write) (scheme complex))
  (begin
    (define %pass 0)
    (define %fail 0)
    (define %depth 0)
    (define %error-marker (list '<error>))

    ;; Catch exceptions without `guard` (which currently expands to an internal
    ;; %guard-eval not visible inside a library env): call/cc + with-exception-
    ;; handler, both real primitives exported by (scheme base).
    (define (%try thunk on-error)
      (call-with-current-continuation
        (lambda (k)
          (with-exception-handler
            (lambda (e) (k (on-error e)))
            thunk))))

    (define (test-runner-fail-count) %fail)

    (define (%nan? x) (and (number? x) (real? x) (not (= x x))))
    (define (%inexact-real? x) (and (real? x) (inexact? x)))
    (define (%approx=? a b)
      (let ((eps 1e-6))   ; relative; loose enough to ignore last-ULP noise
        (<= (abs (- a b)) (* eps (max 1.0 (abs a) (abs b))))))
    ;; equal?, but NaN=NaN and inexact reals compared approximately (matches
    ;; (chibi test)'s float handling so float tests don't spuriously fail).
    (define (%same? expected actual)
      (cond
        ;; identical -- also makes +inf.0 = +inf.0 etc. (subtraction would NaN)
        ((eqv? expected actual) #t)
        ((and (%nan? expected) (%nan? actual)) #t)
        ((and (%inexact-real? expected) (%inexact-real? actual))
         (%approx=? expected actual))
        ;; inexact complex: compare real and imaginary parts approximately
        ((and (number? expected) (number? actual)
              (inexact? expected) (inexact? actual)
              (or (not (real? expected)) (not (real? actual))))
         (and (%approx=? (real-part expected) (real-part actual))
              (%approx=? (imag-part expected) (imag-part actual))))
        (else (equal? expected actual))))

    (define (%fail! name expected actual)
      (set! %fail (+ %fail 1))
      (display "FAIL ") (write name)
      (display " expected ") (write expected)
      (display " got ") (write actual) (newline))

    (define (%run name expected thunk)
      (let ((actual (%try thunk (lambda (e) %error-marker))))
        (cond
          ((eq? actual %error-marker) (%fail! name expected '<raised-error>))
          ((%same? expected actual) (set! %pass (+ %pass 1)))
          (else (%fail! name expected actual)))))

    (define-syntax test
      (syntax-rules ()
        ((_ expected expr) (%run 'expr expected (lambda () expr)))
        ((_ name expected expr) (%run name expected (lambda () expr)))))

    (define-syntax test-equal
      (syntax-rules ()
        ((_ expected expr) (test expected expr))
        ((_ name expected expr) (test name expected expr))))

    (define-syntax test-eqv
      (syntax-rules ()
        ((_ expected expr) (test expected expr))))

    (define (%run-assert name thunk)
      (let ((v (%try thunk (lambda (e) %error-marker))))
        (if (and (not (eq? v %error-marker)) v)
            (set! %pass (+ %pass 1))
            (%fail! name 'true v))))
    (define-syntax test-assert
      (syntax-rules ()
        ((_ expr) (%run-assert 'expr (lambda () expr)))
        ((_ name expr) (%run-assert name (lambda () expr)))))

    (define (%run-error name thunk)
      (let ((raised (%try (lambda () (thunk) #f) (lambda (e) #t))))
        (if raised
            (set! %pass (+ %pass 1))
            (%fail! name '<error-expected> 'no-error))))
    ;; (test-error expr) / (test-error pred expr) / (test-error name pred expr)
    ;; -- we only check that an error is raised, ignoring any predicate.
    (define-syntax test-error
      (syntax-rules ()
        ((_ expr) (%run-error 'expr (lambda () expr)))
        ((_ a expr) (%run-error 'expr (lambda () expr)))
        ((_ a b expr) (%run-error 'expr (lambda () expr)))))

    (define-syntax test-values
      (syntax-rules ()
        ((_ expected expr)
         (%run 'expr
               (call-with-values (lambda () expected) list)
               (lambda () (call-with-values (lambda () expr) list))))))

    (define-syntax test-begin
      (syntax-rules ()
        ((_) (set! %depth (+ %depth 1)))
        ((_ name) (set! %depth (+ %depth 1)))))
    (define (%test-end)
      (set! %depth (- %depth 1))
      (if (<= %depth 0)
          (begin
            (display "=== ") (display %pass) (display " passed, ")
            (display %fail) (display " failed ===") (newline))))
    (define-syntax test-end
      (syntax-rules ()
        ((_) (%test-end))
        ((_ name) (%test-end))))

    (define-syntax test-group
      (syntax-rules ()
        ((_ name body ...) (begin (test-begin name) body ... (test-end name)))))
    ))
