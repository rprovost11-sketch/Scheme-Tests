;;; metamorphic-strings.scm -- property-based string/UTF-8 tester (Phase 4).
;;;
;;; Fourth metamorphic sibling, aimed at the string surface under UTF-8 stress --
;;; the area with the richest bug history (Phase 3 scarred a string-set! byte-vs-
;;; code-point bug). A deterministic generator builds strings mixing 1-, 2-, 3-,
;;; and 4-byte UTF-8 characters and asserts indexing/slicing invariants that must
;;; hold for any correctly code-point-indexed string implementation. The invariant
;;; is the oracle, so this catches byte-vs-code-point bugs that BOTH ports share.
;;;
;;; Run:  python -m pyscheme metamorphic-strings.scm   (or the cppscheme2 exe)

(define seed 2654435761)
(define (rand!)
  (set! seed (modulo (+ (* seed 1103515245) 12345) 2147483648))
  seed)
(define (rand-below n) (modulo (rand!) n))

;; chars across all UTF-8 byte-lengths: ASCII, 2-byte, 3-byte, 4-byte.
(define char-pool
  (list #\a #\Z #\0 #\space            ; 1-byte
        (integer->char #x03BB)         ; lambda, 2-byte
        (integer->char #x00E9)         ; e-acute, 2-byte
        (integer->char #x2603)         ; snowman, 3-byte
        (integer->char #x4E2D)         ; CJK, 3-byte
        (integer->char #x1F600)        ; emoji, 4-byte
        (integer->char #x1D11E)))      ; musical G-clef, 4-byte
(define (gen-char) (list-ref char-pool (rand-below (length char-pool))))
(define (gen-string)
  (let ((n (rand-below 10)))
    (let loop ((i 0) (acc '()))
      (if (= i n) (list->string (reverse acc))
          (loop (+ i 1) (cons (gen-char) acc))))))

(define total 0)
(define fails 0)
(define (check name ok)
  (set! total (+ total 1))
  (if (not ok)
      (begin (set! fails (+ fails 1)) (display "FAIL: ") (write name) (newline))))

(define (laws s)
  (let* ((cs  (string->list s))
         (len (string-length s)))
    ;; code-point length matches the char list
    (check (list 'len s) (= len (length cs)))
    ;; string<->list round-trips
    (check (list 'list-rt s) (string=? s (list->string cs)))
    ;; reverse twice is identity
    (check (list 'rev2 s) (string=? s (list->string (reverse (reverse cs)))))
    ;; string-ref agrees with the char list at every index
    (do ((i 0 (+ i 1))) ((= i len))
      (check (list 'ref s i) (char=? (string-ref s i) (list-ref cs i))))
    ;; a split + append reconstructs the original at every cut point
    (do ((k 0 (+ k 1))) ((> k len))
      (check (list 'split s k)
             (string=? s (string-append (substring s 0 k) (substring s k len)))))))

(do ((i 0 (+ i 1))) ((= i 400))
  (laws (gen-string)))

(display total) (display " checks, ") (display fails) (display " failed") (newline)
