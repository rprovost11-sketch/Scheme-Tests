;;; Deeper ellipsis: a let-like macro that splices two parallel sequences,
;;; plus a zip that pairs two equal-length syntactic lists.
(define-syntax my-let
  (syntax-rules ()
    ((_ ((name val) ...) body ...)
     ((lambda (name ...) body ...) val ...))))

(write (my-let ((a 1) (b 2) (c 3)) (+ a b c)))
(newline)

(define-syntax pairup
  (syntax-rules ()
    ((_ (k ...) (v ...)) (list (cons k v) ...))))

(write (pairup (1 2 3) (10 20 30)))
(newline)
