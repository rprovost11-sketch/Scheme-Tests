(define-library (test user)
  (export hypotenuse labeled-square)
  (import (scheme base) (scheme inexact) (test math))
  (begin
    (define (hypotenuse a b) (sqrt (sum-of-squares a b)))
    (define (labeled-square x) (list 'square-of x '= (square x)))))
