;;; Literal identifiers in patterns: a cond-like macro keying on => and else.
(define-syntax my-cond
  (syntax-rules (=> else)
    ((_ (else e ...)) (begin e ...))
    ((_ (test => proc) clause ...)
     (let ((t test)) (if t (proc t) (my-cond clause ...))))
    ((_ (test e ...) clause ...)
     (if test (begin e ...) (my-cond clause ...)))
    ((_) (if #f #f))))

(write (my-cond ((assv 2 '((1 . a) (2 . b))) => cdr)
                (else 'none)))
(newline)
(write (my-cond (#f 'no) (else 'fell-through)))
(newline)
