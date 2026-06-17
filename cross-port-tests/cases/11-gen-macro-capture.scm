;;; A macro-generating macro whose generated template introduces a binding
;;; (let ((y 'inner)) ...) using the THREADED identifier y, while a use-site
;;; reference of the same name must stay uncaptured.  (This is the A1f case
;;; from the hygiene acceptance battery -- the standing caveat case.)
(define x 'outer)
(define-syntax foo
  (syntax-rules ()
    ((foo bar y)
     (define-syntax bar
       (syntax-rules ()
         ((bar e) (let ((y 'inner)) (list y e))))))))
(foo bar x)
(write (list (bar x) x))   ; expect ((inner outer) outer)
(newline)
