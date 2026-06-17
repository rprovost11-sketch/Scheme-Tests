;;; Broadcasting a depth-0 pattern variable into a depth-1 ellipsis template:
;;; `x` (matched once) is replicated alongside each `y` of `(y ...)`.
(define-syntax distribute
  (syntax-rules ()
    ((_ x (y ...)) (list (cons x y) ...))))

(write (distribute 9 (1 2 3)))   ; => ((9 . 1) (9 . 2) (9 . 3))
(newline)
