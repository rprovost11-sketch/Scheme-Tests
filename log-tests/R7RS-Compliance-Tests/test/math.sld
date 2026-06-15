(define-library (test math)
  (export square cube sum-of-squares)
  (import (scheme base))
  (begin
    (define (square x) (* x x))
    (define (cube x) (* x x x))
    (define (sum-of-squares a b) (+ (square a) (square b)))))
