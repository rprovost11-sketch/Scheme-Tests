(define-library (test syntax)
  (export my-when my-swap!)
  (import (scheme base))
  (begin
    (define-syntax my-when
      (syntax-rules ()
        ((my-when test expr ...)
         (if test (begin expr ...) (if #f #f)))))
    (define-syntax my-swap!
      (syntax-rules ()
        ((my-swap! a b)
         (let ((tmp a))
           (set! a b)
           (set! b tmp)))))))
