;;; Vector patterns and templates in syntax-rules (R7RS 4.3.2).
(define-syntax vec-sum
  (syntax-rules ()
    ((_ #(a ...)) (+ a ...))))

(define-syntax revec
  (syntax-rules ()
    ((_ #(a b ...)) #(b ... a))))

(write (vec-sum #(1 2 3 4)))
(newline)
(write (revec #(1 2 3)))
(newline)
