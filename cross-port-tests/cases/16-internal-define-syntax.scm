;;; Internal define-syntax: a macro defined in a body and used within it.
(define (f x)
  (define-syntax dbl (syntax-rules () ((_ n) (* 2 n))))
  (dbl x))

(write (f 21))   ; => 42
(newline)
