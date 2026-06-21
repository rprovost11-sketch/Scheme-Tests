;;; cross-port-common.scm -- shared engine for the cpp-vs-py differential suites.
;;;
;;; LOADED (not imported) by diff.scm and fuzz.scm after their own (import ...);
;;; it relies on (scheme base) being in scope plus the run-process / interpreter-argv
;;; extension primitives.  This is the Scheme analogue of fuzz.py's `import diff`:
;;; the normalization, stderr-core stripping, per-case run, and divergence
;;; classification live here so both harnesses compare the two ports identically.

;; ---- small helpers (R7RS-small lacks filter / string ops) ----------------------

(define (xfilter pred lst)
  (cond ((null? lst) '())
        ((pred (car lst)) (cons (car lst) (xfilter pred (cdr lst))))
        (else (xfilter pred (cdr lst)))))

(define (string-suffix? suf s)
  (let ((ls (string-length s)) (lu (string-length suf)))
    (and (>= ls lu) (string=? (substring s (- ls lu) ls) suf))))

(define (index-of s c from)                ; index of char c in s at/after `from`, or #f
  (let ((n (string-length s)))
    (let loop ((i from))
      (cond ((>= i n) #f)
            ((char=? (string-ref s i) c) i)
            (else (loop (+ i 1)))))))

(define (ws? c) (or (char=? c #\space) (char=? c #\tab)))
(define (word-char? c)
  (or (char<=? #\a c #\z) (char<=? #\A c #\Z) (char<=? #\0 c #\9) (char=? c #\_)))

(define (trim-left-ws s)
  (let ((n (string-length s)))
    (let loop ((i 0))
      (if (and (< i n) (ws? (string-ref s i))) (loop (+ i 1)) (substring s i n)))))

(define (rstrip-ws s)
  (let loop ((i (string-length s)))
    (if (and (> i 0) (ws? (string-ref s (- i 1)))) (loop (- i 1)) (substring s 0 i))))

(define (string-split-newline s)
  (let ((n (string-length s)))
    (let loop ((start 0) (i 0) (acc '()))
      (cond ((>= i n) (reverse (cons (substring s start n) acc)))
            ((char=? (string-ref s i) #\newline)
             (loop (+ i 1) (+ i 1) (cons (substring s start i) acc)))
            (else (loop start (+ i 1) acc))))))

(define (remove-cr s)
  (let ((out (open-output-string)))
    (string-for-each (lambda (c) (unless (char=? c #\return) (write-char c out))) s)
    (get-output-string out)))

(define (rstrip-newlines s)
  (let loop ((i (string-length s)))
    (if (and (> i 0) (char=? (string-ref s (- i 1)) #\newline)) (loop (- i 1))
        (substring s 0 i))))

;; CRLF -> LF; rstrip each line; rstrip trailing newlines (== diff.py normalize).
(define (normalize raw)
  (let ((lines (map rstrip-ws (string-split-newline (remove-cr raw)))))
    (rstrip-newlines
     (let join ((ls lines) (acc ""))
       (cond ((null? ls) acc)
             ((string=? acc "") (join (cdr ls) (car ls)))
             (else (join (cdr ls) (string-append acc "\n" (car ls)))))))))

(define (first-line s)
  (let ((nl (index-of s #\newline 0))) (if nl (substring s 0 nl) s)))

(define (strip-prog-tag line)              ; drop leading "\w+:\s*"
  (let* ((s (trim-left-ws line)) (n (string-length s)))
    (let loop ((i 0))
      (cond ((and (< i n) (word-char? (string-ref s i))) (loop (+ i 1)))
            ((and (> i 0) (< i n) (char=? (string-ref s i) #\:))
             (trim-left-ws (substring s (+ i 1) n)))
            (else line)))))

;; drop leading '"<path>" line N, col C: ' (pyScheme file-mode location); the
;; loc-ending colon is the first colon after the closing quote (a drive-letter
;; colon is inside the quotes, before it).
(define (strip-py-loc s)
  (if (or (= 0 (string-length s)) (not (char=? (string-ref s 0) #\")))
      s
      (let ((close (index-of s #\" 1)))
        (if (not close) s
            (let ((colon (index-of s #\: (+ close 1))))
              (if colon (trim-left-ws (substring s (+ colon 1) (string-length s))) s))))))

(define (stderr-core raw)
  (let ((line (first-line (normalize raw))))
    (if (string=? line "") "" (strip-py-loc (strip-prog-tag line)))))

;; ---- the two ports + per-case run/compare --------------------------------------

(define py-argv (interpreter-argv))                       ; self (py); PYTHONPATH inherited
(define cpp-argv (list "../../4CPPScheme2/build/Release/cppscheme2.exe"))  ; sibling, known path

;; run one case file through ARGV in file mode -> (vector out-norm err-core rc)
(define (run-case argv casefile)
  (call-with-values (lambda () (run-process (append argv (list casefile))))
    (lambda (rc out err) (vector (normalize out) (stderr-core err) rc))))

(define (out-of r) (vector-ref r 0))
(define (err-of r) (vector-ref r 1))
(define (rc-of  r) (vector-ref r 2))

(define (behaves-like? a b)
  (and (string=? (out-of a) (out-of b))
       (= (rc-of a) (rc-of b))
       (string=? (err-of a) (err-of b))))

(define (divergence-kind a b)
  (cond ((not (string=? (out-of a) (out-of b))) "VALUE")   ; different output -- worst
        ((not (= (rc-of a) (rc-of b))) "EXIT")             ; one errored, other not
        (else "ERRMSG")))                                  ; both errored, differently

(define (show label r)
  (display "          [") (display label) (display " rc=") (display (rc-of r)) (display "]") (newline)
  (for-each (lambda (ln) (display "            out| ") (display ln) (newline))
            (string-split-newline (if (string=? (out-of r) "") "<no stdout>" (out-of r))))
  (unless (string=? (err-of r) "")
    (display "            err| ") (display (err-of r)) (newline)))

;; ---- optional chibi oracle (opt-in: CROSS_PORT_ORACLE=chibi; skip-if-absent) ---
;; The bare cross-port diff cannot catch a bug BOTH ports share.  With the oracle
;; on, chibi (the R7RS reference) is consulted on every case: it adjudicates which
;; port is wrong on a divergence, and flags a SHARED-DEVIATION on parity (both
;; ports agree but differ from chibi).  Off by default so the registry/CI (which
;; have no chibi) are unaffected.  Needs (scheme file) + (scheme process-context)
;; from the loader.

(define chibi-exe
  (or (get-environment-variable "CHIBI_EXE") "D:/SWDEV/tools/chibi-scheme/chibi-scheme.exe"))
(define chibi-lib
  (or (get-environment-variable "CHIBI_LIB") "D:/SWDEV/tools/chibi-scheme/lib"))
(define oracle?
  (and (equal? (get-environment-variable "CROSS_PORT_ORACLE") "chibi")
       (file-exists? chibi-exe)))

(define %chibi-sentinel "<<<CHIBI-ERR>>>")

;; substring search -> index or #f
(define (str-find s sub from)
  (let ((sn (string-length s)) (un (string-length sub)))
    (let loop ((i from))
      (cond ((> (+ i un) sn) #f)
            ((string=? (substring s i (+ i un)) sub) i)
            (else (loop (+ i 1)))))))

;; Run CASEFILE through chibi via an eval-in-interaction-env driver (so the
;; program's own output lands on clean stdout and chibi's file-compiler quirk with
;; macro-generated define-syntax is sidestepped).  The driver READS the case file
;; directly (no string escaping).  Returns (vector out errored?) or #f if absent.
(define (run-chibi casefile)
  (if (not oracle?) #f
      (let ((driver (string-append
              "(import (scheme base) (scheme write) (scheme eval) (scheme repl) (scheme read)"
              " (scheme file) (scheme char) (scheme inexact) (scheme complex) (scheme cxr)"
              " (scheme lazy) (scheme case-lambda))\n"
              "(define ie (interaction-environment))\n"
              "(define (e->s e) (if (error-object? e) (error-object-message e)"
              " (let ((p (open-output-string))) (write e p) (get-output-string p))))\n"
              "(guard (e (#t (write-string \"" %chibi-sentinel "\") (write-string (e->s e))))\n"
              "  (call-with-input-file \"" casefile "\"\n"
              "    (lambda (p) (let loop () (let ((f (read p)))\n"
              "      (unless (eof-object? f) (eval f ie) (loop)))))))\n"))
            (df "chibi-driver-scratch.scm"))
        (when (file-exists? df) (delete-file df))
        (call-with-output-file df (lambda (p) (write-string driver p)))
        (call-with-values
          (lambda () (run-process (list chibi-exe "-I" chibi-lib df) #f 30))
          (lambda (code out err)
            (let* ((o (normalize out)) (s (str-find o %chibi-sentinel 0)))
              (if s (vector (rstrip-newlines (substring o 0 s)) #t)
                  (vector o #f))))))))

;; Coarse agreement of a port result with chibi: same output AND same errored-or-not
;; (error WORDING is never compared -- chibi phrases its own way).
(define (matches-oracle? port-r chibi-r)
  (and (string=? (out-of port-r) (vector-ref chibi-r 0))
       (eq? (not (= (rc-of port-r) 0)) (vector-ref chibi-r 1))))

(define (show-chibi ch)
  (display "          [chibi errored=") (display (vector-ref ch 1)) (display "]") (newline)
  (for-each (lambda (ln) (display "            out| ") (display ln) (newline))
            (string-split-newline (if (string=? (vector-ref ch 0) "") "<no stdout>" (vector-ref ch 0)))))

(define (adjudicate py cpp ch)
  (let ((py-ok (matches-oracle? py ch)) (cpp-ok (matches-oracle? cpp ch)))
    (cond ((and py-ok (not cpp-ok)) "chibi agrees with pyScheme (cppScheme2 is wrong)")
          ((and cpp-ok (not py-ok)) "chibi agrees with cppScheme2 (pyScheme is wrong)")
          ((and py-ok cpp-ok) "both match chibi (ERRMSG-only split?)")
          (else "NEITHER matches chibi -- inspect by hand"))))
