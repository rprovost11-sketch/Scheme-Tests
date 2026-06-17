;;; Basic hygiene: the macro-introduced `tmp` must not capture a user `tmp`.
(define-syntax swap!
  (syntax-rules ()
    ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))

(define tmp 1)
(define y 2)
(swap! tmp y)           ; if `tmp` were captured, this would misbehave
(write (list tmp y))
(newline)
