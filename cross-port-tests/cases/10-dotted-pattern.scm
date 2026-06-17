;;; Dotted (improper) tail patterns: (_ (a . rest)) binds rest to the tail.
(define-syntax head+tail
  (syntax-rules ()
    ((_ (a . rest)) (cons 'a 'rest))))

(write (head+tail (1 2 3)))
(newline)

;; A dotted TEMPLATE, built as quoted data: (a . b).
(define-syntax dotted
  (syntax-rules ()
    ((_ a b) '(a . b))))

(write (dotted 1 2))
(newline)
