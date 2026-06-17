;;; Custom ellipsis identifier (R7RS 4.3.2): (syntax-rules ::: () ...).
(define-syntax my-list
  (syntax-rules ::: ()
    ((_ x :::) (list x :::))))
(write (my-list 1 2 3 4))
(newline)

;; The (... ...) escape, using the DEFAULT ellipsis: an outer macro whose
;; template must emit a literal `...` for the inner syntax-rules it generates.
(define-syntax be-like-begin
  (syntax-rules ()
    ((be-like-begin name)
     (define-syntax name
       (syntax-rules ()
         ((name expr (... ...)) (begin expr (... ...))))))))
(be-like-begin sequence)
(write (sequence 1 2 3))
(newline)
