;;; Nested ellipsis: ((a b ...) ...) -> flatten each group's tail.
(define-syntax firsts
  (syntax-rules ()
    ((_ (a b ...) ...) (list a ...))))

(define-syntax rests
  (syntax-rules ()
    ((_ (a b ...) ...) (list (list b ...) ...))))

(write (firsts (1 2 3) (4 5) (6)))
(newline)
(write (rests (1 2 3) (4 5) (6)))
(newline)
