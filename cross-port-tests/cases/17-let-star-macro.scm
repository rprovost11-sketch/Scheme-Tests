;;; Recursive macro building nested lets (let* by hand): each binding must see
;;; the previous ones, and the per-step `let` bindings must stay hygienic.
(define-syntax my-let*
  (syntax-rules ()
    ((_ () body ...) (begin body ...))
    ((_ ((x v) rest ...) body ...)
     (let ((x v)) (my-let* (rest ...) body ...)))))

(write (my-let* ((a 1) (b (+ a 1)) (c (+ b 1))) (list a b c)))   ; => (1 2 3)
(newline)
