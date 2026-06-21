;;; diff.scm -- cross-port differential macro-expansion harness (shell-free).
;;;
;;; Runs every cases/*.scm through BOTH ports -- pyScheme and cppScheme2 -- in file
;;; mode and compares their behavior.  The ports are MIRROR implementations of the
;;; same language, so any divergence on identical input is, by construction, a bug
;;; in at least one of them; no expected values are stored (the oracle is "the other
;;; port").  Replaces the Python diff.py: it enumerates cases via (directory-files)
;;; and launches each port via (run-process), depending only on the interpreter.
;;;
;;; HOSTED ON pyScheme (registry: ports py).  Reason: the py child must be able to
;;; import the pyscheme package; pyScheme's listener sets PYTHONPATH for the suite,
;;; which run-process children inherit -- so the py side resolves regardless of cwd.
;;; The py side is (interpreter-argv) (self); the cpp side is the sibling exe by a
;;; known relative path.  The comparison is symmetric, so a single host suffices.
;;;
;;; WHAT IS COMPARED (streams kept apart, mirroring diff.py):
;;;   stdout -- the program's written output; compared after newline/trailing-ws
;;;             normalization.  A difference here is a VALUE divergence (the worst).
;;;   exit   -- compared exactly: catches "one errors, the other doesn't" (EXIT).
;;;   stderr -- only its NORMALIZED CORE message is compared: the leading program
;;;             tag ("pyscheme: "/"cppscheme2: ") and pyScheme's source-location
;;;             prefix ('"<path>" line N, col C: ') are stripped, since that chrome
;;;             legitimately differs.  A surviving difference is an ERRMSG divergence.
;;;
;;; Run (from cross-port-tests/, hosted on pyScheme):
;;;   <pyscheme> diff.scm        (exits nonzero if any case diverges)

(import (scheme base) (scheme write))

;; ---- small helpers (R7RS-small has no filter / string-suffix? / string ops) ----

(define (filter pred lst)
  (cond ((null? lst) '())
        ((pred (car lst)) (cons (car lst) (filter pred (cdr lst))))
        (else (filter pred (cdr lst)))))

(define (string-suffix? suf s)
  (let ((ls (string-length s)) (lu (string-length suf)))
    (and (>= ls lu) (string=? (substring s (- ls lu) ls) suf))))

;; index of char c in s at/after `from`, or #f
(define (index-of s c from)
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
      (if (and (< i n) (ws? (string-ref s i))) (loop (+ i 1))
          (substring s i n)))))

(define (rstrip-ws s)        ; drop trailing spaces/tabs
  (let loop ((i (string-length s)))
    (if (and (> i 0) (ws? (string-ref s (- i 1)))) (loop (- i 1))
        (substring s 0 i))))

(define (string-split-newline s)   ; split on #\newline into a list of lines
  (let ((n (string-length s)))
    (let loop ((start 0) (i 0) (acc '()))
      (cond ((>= i n) (reverse (cons (substring s start n) acc)))
            ((char=? (string-ref s i) #\newline)
             (loop (+ i 1) (+ i 1) (cons (substring s start i) acc)))
            (else (loop start (+ i 1) acc))))))

(define (remove-cr s)        ; drop all #\return (CRLF -> LF)
  (let ((out (open-output-string)))
    (string-for-each (lambda (c) (unless (char=? c #\return) (write-char c out))) s)
    (get-output-string out)))

(define (rstrip-newlines s)
  (let loop ((i (string-length s)))
    (if (and (> i 0) (char=? (string-ref s (- i 1)) #\newline)) (loop (- i 1))
        (substring s 0 i))))

;; CRLF -> LF; rstrip each line; rstrip trailing newlines overall (== diff.py normalize)
(define (normalize raw)
  (let* ((s (remove-cr raw))
         (lines (map rstrip-ws (string-split-newline s))))
    (rstrip-newlines
     (let join ((ls lines) (acc ""))
       (cond ((null? ls) acc)
             ((string=? acc "") (join (cdr ls) (car ls)))
             (else (join (cdr ls) (string-append acc "\n" (car ls)))))))))

(define (first-line s)
  (let ((nl (index-of s #\newline 0)))
    (if nl (substring s 0 nl) s)))

;; strip leading "\w+:\s*" (the program-name tag)
(define (strip-prog-tag line)
  (let* ((s (trim-left-ws line)) (n (string-length s)))
    (let loop ((i 0))
      (cond ((and (< i n) (word-char? (string-ref s i))) (loop (+ i 1)))
            ((and (> i 0) (< i n) (char=? (string-ref s i) #\:))
             (trim-left-ws (substring s (+ i 1) n)))
            (else line)))))

;; strip leading '"<path>" line N, col C: ' (pyScheme's file-mode source location).
;; The loc-ending colon is the FIRST colon after the closing quote (any colon in a
;; Windows drive path is inside the quotes, before it).
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

;; ---- the differential ----------------------------------------------------------

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

(define cases
  (filter (lambda (n) (string-suffix? ".scm" n)) (directory-files "cases")))

(display "cross-port differential macro harness") (newline)
(display "  pyScheme  : ") (for-each (lambda (a) (display a) (display " ")) py-argv) (newline)
(display "  cppScheme2: ") (display (car cpp-argv)) (newline) (newline)

(define parity 0)
(define diverged '())

(for-each
 (lambda (name)
   (let* ((cf (string-append "cases/" name))
          (py (run-case py-argv cf))
          (cpp (run-case cpp-argv cf)))
     (if (behaves-like? py cpp)
         (begin (set! parity (+ parity 1))
                (display "  parity   ") (display name) (newline))
         (let ((kind (divergence-kind py cpp)))
           (set! diverged (cons (cons name kind) diverged))
           (display "  DIVERGE  ") (display name) (display "  [") (display kind)
           (display "]  (py rc=") (display (rc-of py)) (display ", cpp rc=")
           (display (rc-of cpp)) (display ")") (newline)
           (show "pyScheme" py) (show "cppScheme2" cpp)))))
 cases)

(newline)
(display "cross-port: ") (display parity) (display " parity, ")
(display (length diverged)) (display " diverged  (of ") (display (length cases))
(display " cases)") (newline)
(for-each (lambda (nk) (display "    DIVERGE  ") (display (cdr nk)) (display "  ")
                       (display (car nk)) (newline))
          (reverse diverged))
(exit (if (null? diverged) 0 1))
