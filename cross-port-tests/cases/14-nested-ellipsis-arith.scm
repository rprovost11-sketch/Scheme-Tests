;;; Nested ellipsis with an inner-depth fold: ((a ...) ...) -> ((+ a ...) ...).
(define-syntax zipsum
  (syntax-rules ()
    ((_ (a ...) ...) (list (+ a ...) ...))))

(write (zipsum (1 2 3) (10 20) (100)))   ; => (6 30 100)
(newline)
