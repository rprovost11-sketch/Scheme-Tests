;;; Hygiene of a macro-INTRODUCED define: the introduced `name` must bind the
;;; user's identifier, while an introduced helper binding stays hygienic
;;; (referenceable from the template, invisible to user code).
(define-syntax def-with-helper
  (syntax-rules ()
    ((_ name val) (begin (define helper val) (define name helper)))))

(def-with-helper bar 7)
(write bar)            ; => 7   (the introduced define bound the user's `bar`)
(newline)
