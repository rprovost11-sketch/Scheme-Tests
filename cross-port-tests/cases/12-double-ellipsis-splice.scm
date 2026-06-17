;;; Double-ellipsis splice in a template: `a ... ...` flattens one level.
(define-syntax flat
  (syntax-rules ()
    ((_ (a ...) ...) (list a ... ...))))

(write (flat (1 2) (3 4 5) (6)))   ; => (1 2 3 4 5 6)
(newline)
