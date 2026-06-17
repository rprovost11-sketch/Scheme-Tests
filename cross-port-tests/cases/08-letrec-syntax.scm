;;; letrec-syntax: mutually-recursive transformers that terminate STRUCTURALLY
;;; (recursing over syntactic tokens, not runtime values), plus let-syntax
;;; scoping (the inner binding must shadow only within its body).
(write
 (letrec-syntax
     ((my-even? (syntax-rules () ((_) #t) ((_ a b ...) (my-odd? b ...))))
      (my-odd?  (syntax-rules () ((_) #f) ((_ a b ...) (my-even? b ...)))))
   (list (my-even? x x x x) (my-odd? x x x))))
(newline)

(define-syntax m (syntax-rules () ((_) 'outer)))
(write (list (m)
             (let-syntax ((m (syntax-rules () ((_) 'inner)))) (m))
             (m)))
(newline)
