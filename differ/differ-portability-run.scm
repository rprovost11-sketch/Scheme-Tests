;;; differ-portability-run.scm -- cross-implementation runner for the differ-core
;;; portability test.  Launches differ-portability.scm on every AVAILABLE Scheme
;;; (the two ports always; chibi / Chez / Gauche when their exe is present) and checks
;;; that each prints the SAME canonical line, equal to the all-correct expected line.
;;; This is the committed proof that the differ's classification core is genuinely
;;; portable R7RS, not accidentally tied to cppScheme2/pyScheme behaviour.
;;;
;;; The two ports run as subprocesses too (not in-process) so the portability test's
;;; primitive-shadowing stubs never touch this runner's own environment.  External
;;; interpreters are SKIPPED (not failed) when absent, so this passes on a bare machine
;;; using just the two ports; install chibi/Chez/Gauche to widen the proof.
;;;
;;; Exe locations come from env vars (CPP_EXE / PY_EXE / GOSH_EXE / CHIBI_EXE +
;;; CHIBI_LIB / CHEZ_EXE) with the local defaults; run with cwd = scheme-tests/differ.
;;; Exits 0 iff every interpreter that ran matched the expected line.

(import (scheme base) (scheme write) (scheme process-context))

(define (env-or k d) (or (get-environment-variable k) d))

(define (string-suffix? suf s)
  (let ((ls (string-length s)) (lu (string-length suf)))
    (and (>= ls lu) (string=? (substring s (- ls lu) ls) suf))))

;; The two ports: this one (interpreter-argv) and its sibling.
(define host-argv    (interpreter-argv))
(define host-is-cpp? (string-suffix? "cppscheme2.exe" (car host-argv)))
(define cpp-exe      (env-or "CPP_EXE" "../../4CPPScheme2/build/Release/cppscheme2.exe"))
(define py-launch    (list (env-or "PY_EXE" "python") "-m" "pyscheme"))
(define sibling-argv (if host-is-cpp? py-launch (list cpp-exe)))
(define host-name    (if host-is-cpp? "cppScheme2" "pyScheme"))
(define sibling-name (if host-is-cpp? "pyScheme"   "cppScheme2"))

;; External reference Schemes (skip-if-absent).
(define gosh-exe  (env-or "GOSH_EXE"  "C:/Program Files/Gauche/bin/gosh.exe"))
(define chibi-exe (env-or "CHIBI_EXE" "D:/SWDEV/tools/chibi-scheme/chibi-scheme.exe"))
(define chibi-lib (env-or "CHIBI_LIB" "D:/SWDEV/tools/chibi-scheme/lib"))
(define chez-exe  (env-or "CHEZ_EXE"  "C:/Program Files/Chez Scheme 10.4.1/bin/a6nt/scheme.exe"))

(define PORT      "differ-portability.scm")
(define PORT-CHEZ "differ-portability-chez.scm")

;; A spec = (name argv always?) ; always? = run unconditionally (the two ports);
;; otherwise run only when (car argv) is an existing file.
(define specs
  (list
   (list host-name    (append host-argv    (list PORT))      #t)
   (list sibling-name (append sibling-argv  (list PORT))      #t)
   (list "Gauche"     (list gosh-exe  "-r7"            PORT)      #f)
   (list "Chibi"      (list chibi-exe "-I" chibi-lib   PORT)      #f)
   (list "Chez"       (list chez-exe  "--script"       PORT-CHEZ) #f)))

(define expected "(peer-agree #t peer-diverge #t ref-ok #t ref-bad #t coarse #t strict #t)")

;; --- helpers --------------------------------------------------------------------
(define (trim s)                       ; strip leading/trailing space/tab/CR
  (define (ws? c) (or (char=? c #\space) (char=? c #\tab) (char=? c #\return)))
  (let ((n (string-length s)))
    (let a ((i 0))
      (cond ((and (< i n) (ws? (string-ref s i))) (a (+ i 1)))
            (else (let b ((j n))
                    (if (and (> j i) (ws? (string-ref s (- j 1)))) (b (- j 1))
                        (substring s i j))))))))

(define (prefix? p s)
  (and (>= (string-length s) (string-length p))
       (string=? (substring s 0 (string-length p)) p)))

;; first line of STDOUT that (after trimming) starts with "(peer-agree", or "".
(define (canonical-line stdout)
  (let ((n (string-length stdout)))
    (let loop ((i 0) (start 0))
      (define (line-at end)
        (let ((ln (trim (substring stdout start end))))
          (if (prefix? "(peer-agree" ln) ln #f)))
      (cond ((>= i n) (or (line-at n) ""))
            ((char=? (string-ref stdout i) #\newline)
             (or (line-at i) (loop (+ i 1) (+ i 1))))
            (else (loop (+ i 1) start))))))

;; run one spec; return (name . result-string) where result is the canonical line,
;; "SKIPPED" (absent), or a short failure token.
(define (run-spec spec)
  (let ((name (car spec)) (argv (cadr spec)) (always? (caddr spec)))
    (if (and (not always?) (not (file-exists? (car argv))))
        (cons name 'skipped)
        (call-with-values
          (lambda () (run-process argv "" 60))
          (lambda (rc out err)
            (let ((line (canonical-line out)))
              (cons name (if (string=? line "") 'no-output line))))))))

(define results (map run-spec specs))

;; --- report ---------------------------------------------------------------------
(define ran     (filter (lambda (r) (not (eq? (cdr r) 'skipped))) results))
(define mismatches
  (filter (lambda (r) (not (equal? (cdr r) expected))) ran))

(display "=== differ-core portability (expected: ") (display expected) (display ") ===")
(newline)
(for-each
 (lambda (r)
   (display "  ")
   (let ((name (car r)) (n (string-length (car r))))
     (display name)
     (let pad ((k (- 12 n))) (when (> k 0) (display " ") (pad (- k 1)))))
   (cond ((eq? (cdr r) 'skipped)   (display "SKIPPED (not installed)"))
         ((eq? (cdr r) 'no-output) (display "*** NO CANONICAL LINE ***"))
         ((equal? (cdr r) expected) (display "ok"))
         (else (display "*** MISMATCH: ") (display (cdr r)) (display " ***")))
   (newline))
 results)
(newline)
(if (null? mismatches)
    (begin
      (display "  ALL ") (display (length ran))
      (display " RUNNING INTERPRETER(S) AGREE ON THE DIFFER CORE") (newline)
      (exit 0))
    (begin
      (display "  *** ") (display (length mismatches))
      (display " INTERPRETER(S) DISAGREED ***") (newline)
      (exit 1)))
