(define-library (test rename)
  (export (rename internal-add public-add)
          (rename internal-mul public-mul)
          version)
  (import (scheme base))
  (begin
    (define (internal-add x y) (+ x y))
    (define (internal-mul x y) (* x y))
    (define version "1.0")))
