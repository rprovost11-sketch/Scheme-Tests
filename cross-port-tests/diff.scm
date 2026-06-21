;;; diff.scm -- cross-port differential macro-expansion harness (shell-free).
;;;
;;; Runs every cases/*.scm through BOTH ports -- pyScheme and cppScheme2 -- in file
;;; mode and compares their behavior.  The ports are MIRROR implementations of the
;;; same language, so any divergence on identical input is, by construction, a bug
;;; in at least one of them; no expected values are stored (the oracle is "the other
;;; port").  Replaces the Python diff.py: it enumerates cases via (directory-files)
;;; and launches each port via (run-process), depending only on the interpreter.
;;;
;;; HOSTED ON pyScheme (registry: ports py).  Reason: the py child must import the
;;; pyscheme package; pyScheme's listener sets PYTHONPATH for the suite, which
;;; run-process children inherit -- so the py side resolves regardless of cwd.  The
;;; py side is (interpreter-argv) (self); the cpp side is the sibling exe by a known
;;; relative path.  The comparison is symmetric, so a single host suffices.
;;;
;;; Compared (streams kept apart, mirroring diff.py): stdout (VALUE divergence),
;;; exit code (EXIT), and the normalized stderr core (ERRMSG) -- see
;;; cross-port-common.scm for the normalization + stripping.
;;;
;;; Run (from cross-port-tests/, hosted on pyScheme):  <pyscheme> diff.scm

(import (scheme base) (scheme write) (scheme file) (scheme process-context))
(load "cross-port-common.scm")     ; normalize, run-case, behaves-like?, chibi oracle, ...

(define cases
  (xfilter (lambda (n) (string-suffix? ".scm" n)) (directory-files "cases")))

(display "cross-port differential macro harness") (newline)
(display "  pyScheme  : ") (for-each (lambda (a) (display a) (display " ")) py-argv) (newline)
(display "  cppScheme2: ") (display (car cpp-argv)) (newline) (newline)

(when oracle? (display "  [+chibi oracle]") (newline))

(define parity 0)
(define diverged '())
(define shared '())          ; both ports agree but differ from chibi

(for-each
 (lambda (name)
   (let* ((cf (string-append "cases/" name))
          (py (run-case py-argv cf))
          (cpp (run-case cpp-argv cf))
          (ch (run-chibi cf)))                 ; #f unless oracle?
     (cond
       ((behaves-like? py cpp)
        (if (and ch (not (matches-oracle? py ch)))
            (begin (set! shared (cons name shared))
                   (display "  SHARED   ") (display name)
                   (display "  (ports agree, differ from chibi)") (newline)
                   (show "py & cpp" py) (show-chibi ch))
            (begin (set! parity (+ parity 1))
                   (display "  parity   ") (display name) (newline))))
       (else
        (let ((kind (divergence-kind py cpp)))
          (set! diverged (cons (cons name kind) diverged))
          (display "  DIVERGE  ") (display name) (display "  [") (display kind)
          (display "]  (py rc=") (display (rc-of py)) (display ", cpp rc=")
          (display (rc-of cpp)) (display ")") (newline)
          (show "pyScheme" py) (show "cppScheme2" cpp)
          (when ch (show-chibi ch)
                (display "          --> ") (display (adjudicate py cpp ch)) (newline)))))))
 cases)

(newline)
(display "cross-port: ") (display parity) (display " parity, ")
(display (length diverged)) (display " diverged")
(when oracle? (display ", ") (display (length shared)) (display " shared-deviation"))
(display "  (of ") (display (length cases)) (display " cases)") (newline)
(for-each (lambda (nk) (display "    DIVERGE  ") (display (cdr nk)) (display "  ")
                       (display (car nk)) (newline))
          (reverse diverged))
(for-each (lambda (n) (display "    SHARED   ") (display n) (newline)) (reverse shared))
(exit (if (and (null? diverged) (null? shared)) 0 1))
