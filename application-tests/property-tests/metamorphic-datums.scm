;;; metamorphic-datums.scm -- property-based datum round-trip tester (Phase 4).
;;;
;;; Sibling of metamorphic-numbers.scm, aimed at the STRUCTURAL/TEXTUAL surface
;;; instead of the numeric tower: a deterministic generator builds random datums
;;; (lists, dotted pairs, vectors, bytevectors, strings with escapes, symbols that
;;; need bar-quoting, special/unicode chars) and asserts the one property every
;;; datum with an external representation must satisfy:
;;;
;;;     (equal? d (read (open-input-string (write-string-of d))))      ; write then read
;;;
;;; The property is the oracle, so it catches reader/printer bugs that BOTH mirror
;;; ports share. Numbers are kept to small exact ints here (the numeric tower is
;;; metamorphic-numbers.scm's job), so a failure here points at structure/text.
;;; A read error during the round-trip counts as a failure (guarded).
;;;
;;; Run:  python -m pyscheme metamorphic-datums.scm   (or the cppscheme2 exe)
;;;
;;; CURRENT RESULTS (2026-06-18): BOTH ports 500 datums, 2 failed -- a NEW *shared*
;;; bug (differential testing can't see it, since the ports agree). `write` fails to
;;; bar-quote symbols whose names are not valid bare identifiers: (write (string->
;;; symbol "@")) => bare `@` and (write (string->symbol ".9t")) => bare `.9t`, both
;;; of which then error on read. R7RS requires |@| and |.9t|. The existing bar-quote
;;; logic handles numeric-looking names (the Phase-3 scar) but not `@`/dot-digit
;;; names. KNOWN-OPEN (not fixed, per the freeze). When the writer's needs-quoting
;;; predicate is completed, both ports pass clean and this can join the gated suite.

;; ---- deterministic PRNG ----------------------------------------------------
(define seed 305419896)
(define (rand!)
  (set! seed (modulo (+ (* seed 1103515245) 12345) 2147483648))
  seed)
(define (rand-below n) (modulo (rand!) n))

;; ---- atom generators -------------------------------------------------------
;; Syntactically significant + edge chars, plus a couple of non-ASCII.
(define interesting-chars
  (list #\space #\newline #\tab #\" #\\ #\| #\( #\) #\; #\' #\` #\,
        #\# #\a #\Z #\0 #\9 #\. #\x41 #\x3BB #\x2603))   ; A, lambda, snowman
(define (gen-char)
  (if (< (rand-below 3) 2)
      (list-ref interesting-chars (rand-below (length interesting-chars)))
      (integer->char (+ 33 (rand-below 94)))))           ; printable ASCII

(define (gen-string)
  (let ((n (rand-below 8)))
    (let loop ((i 0) (acc '()))
      (if (= i n) (list->string (reverse acc))
          (loop (+ i 1) (cons (gen-char) acc))))))

(define (gen-symbol) (string->symbol (gen-string)))      ; may need bar-quoting

(define (gen-atom)
  (case (rand-below 5)
    ((0) (* (if (= 0 (rand-below 2)) 1 -1) (rand-below 10000)))
    ((1) (= 0 (rand-below 2)))
    ((2) (gen-char))
    ((3) (gen-string))
    (else (gen-symbol))))

;; ---- compound generators (depth-limited) -----------------------------------
(define (gen-seq depth n)
  (let loop ((i 0) (acc '()))
    (if (= i n) (reverse acc)
        (loop (+ i 1) (cons (gen-datum (- depth 1)) acc)))))

(define (gen-list depth)   (gen-seq depth (rand-below 5)))
(define (gen-vector depth) (list->vector (gen-seq depth (rand-below 5))))
(define (gen-bytevector)
  (let ((n (rand-below 6)))
    (let loop ((i 0) (acc '()))
      (if (= i n) (apply bytevector (reverse acc))
          (loop (+ i 1) (cons (rand-below 256) acc))))))
(define (gen-dotted depth)                               ; improper list
  (let ((n (+ 1 (rand-below 3))))
    (let loop ((i 0) (tail (gen-atom)))
      (if (= i n) tail
          (loop (+ i 1) (cons (gen-datum (- depth 1)) tail))))))

(define (gen-datum depth)
  (if (or (<= depth 0) (< (rand-below 3) 1))
      (gen-atom)
      (case (rand-below 4)
        ((0) (gen-list depth))
        ((1) (gen-dotted depth))
        ((2) (gen-vector depth))
        (else (gen-bytevector)))))

;; ---- property + harness ----------------------------------------------------
(define (write-string-of d)
  (let ((p (open-output-string))) (write d p) (get-output-string p)))

(define total 0)
(define fails 0)
(define (roundtrip d)
  (set! total (+ total 1))
  (let ((s (write-string-of d)))
    (let ((ok (guard (e (#t #f))
                (equal? d (read (open-input-string s))))))
      (if (not ok)
          (begin (set! fails (+ fails 1))
                 (display "FAIL: write=>") (write s) (newline))))))

;; ---- run -------------------------------------------------------------------
(do ((i 0 (+ i 1))) ((= i 500))
  (roundtrip (gen-datum 4)))

(display total) (display " datums, ") (display fails) (display " failed") (newline)
