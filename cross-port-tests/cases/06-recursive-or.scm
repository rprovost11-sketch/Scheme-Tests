;;; Recursive macro with a hygienic temp binding (R7RS `or` expansion).
;;; The `t` binding must not capture a user reference passed in the tail.
(define-syntax my-or
  (syntax-rules ()
    ((_) #f)
    ((_ e) e)
    ((_ e1 e2 ...) (let ((t e1)) (if t t (my-or e2 ...))))))

(write (my-or #f #f 3))
(newline)

;; Hygiene stress: a user variable named `t` flows through the recursion.
(define t 'user-t)
(write (my-or #f t))
(newline)
