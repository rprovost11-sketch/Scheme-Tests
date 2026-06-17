;;; Ellipsis followed by a FIXED tail pattern: (_ x ... last).
;;; R7RS permits a fixed number of patterns after an ellipsis; the matcher
;;; must back off the right number of trailing forms.
(define-syntax but-last-and-last
  (syntax-rules ()
    ((_ x ... last) (cons (list x ...) 'last))))

(write (but-last-and-last 1 2 3 4))
(newline)
(write (but-last-and-last 9))
(newline)
