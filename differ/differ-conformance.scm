;;; differ-conformance.scm -- run a .log golden suite through a CROSS-IMPLEMENTATION
;;; oracle (chibi by default) and report where it disagrees with the golden.  This is
;;; differ(reference = .log golden, subject = chibi, COARSE/conformance) -- the same
;;; engine as differ-battery, but the subject is a different Scheme that formats values
;;; its own way, so the compare is a CONFORMANCE verdict (mirroring chibi_diff.py, the
;;; tool this subsumes) rather than a byte-strict match:
;;;   * golden says %optional-error%      -> always agree (R7RS "it is an error")
;;;   * golden expects an error           -> agree iff the oracle raised ANY error
;;;   * golden expects a return value     -> agree iff oracle didn't error and its
;;;                                          value matches (normalised; ==> X or ==> Y)
;;;   * golden is output-only             -> agree iff oracle didn't error and its
;;;                                          captured output matches (normalised)
;;; Disagreements are the REPORT (a different impl legitimately differs); they flag
;;; spec questions / golden errors / oracle quirks for a human, so this exits 0 on a
;;; clean run regardless of the disagreement count (nonzero only if the oracle can't
;;; be launched).  Skips with exit 0 if the oracle exe is absent.
;;;
;;; Oracle via env (defaults = chibi): CONF_EXE, CONF_LIB (one -I dir), CONF_DRIVER
;;; (the matching driver; chibi-driver.scm by default).  Point CONF_EXE/CONF_DRIVER at
;;; another R7RS Scheme (e.g. Chez with a chez-driver.scm) to reuse the whole harness.
;;;
;;; Run from the suite dir with --no-rc (like differ-battery):
;;;   cd scheme-tests/log-tests/feature-tests
;;;   <interp> --no-rc ../../differ/differ-conformance.scm

(import (scheme base) (scheme write) (scheme file) (scheme process-context) (scheme read))

(define differ-home (or (get-environment-variable "DIFFER_HOME") "../../differ"))
(load (string-append differ-home "/differ.scm"))
(define suite-dir (or (get-environment-variable "DIFFER_SUITE") "."))

(define conf-exe (or (get-environment-variable "CONF_EXE")
                     "D:/SWDEV/tools/chibi-scheme/chibi-scheme.exe"))
(define conf-lib (or (get-environment-variable "CONF_LIB")
                     "D:/SWDEV/tools/chibi-scheme/lib"))
(define conf-driver (or (get-environment-variable "CONF_DRIVER")
                        (string-append differ-home "/chibi-driver.scm")))
(define conf-name (or (get-environment-variable "CONF_NAME") "chibi"))

(when (not (file-exists? conf-exe))
  (display "differ-conformance: oracle not found (") (display conf-exe)
  (display ") -- skipping.") (newline)
  (exit 0))

;; ---- conformance compare (golden vs oracle) -----------------------------------

(define (str-prefix? pre s)
  (let ((lp (string-length pre)) (ls (string-length s)))
    (and (>= ls lp) (string=? (substring s 0 lp) pre))))

(define (norm s)                               ; trim trailing ws on the whole string
  (let loop ((i (string-length s)))
    (if (and (> i 0)
             (let ((c (string-ref s (- i 1))))
               (or (char=? c #\space) (char=? c #\tab)
                   (char=? c #\newline) (char=? c #\return))))
        (loop (- i 1))
        (substring s 0 i))))

;; actual value matches expected, honouring '==> X or ==> Y' alternatives.
(define (retval-conform? actual expected)
  (let ((a (norm actual)))
    (let scan ((e expected))
      (let ((sep (let find ((i 0))                ; index of " or ==> " in e, or #f
                   (cond ((> (+ i 8) (string-length e)) #f)
                         ((string=? (substring e i (+ i 8)) " or ==> ") i)
                         (else (find (+ i 1)))))))
        (if sep
            (or (string=? a (norm (substring e 0 sep)))
                (scan (substring e (+ sep 8) (string-length e))))
            (string=? a (norm e)))))))

(define (cycle-conformance-match? golden oracle)
  (let ((ge (cycle-error golden)) (gr (cycle-retval golden)) (go (cycle-output golden))
        (oe (cycle-errored? oracle)))
    (cond
      ((str-prefix? "%optional-error%" ge) #t)
      ((> (string-length ge) 0) oe)                 ; golden expects ANY error
      ((> (string-length gr) 0)                     ; golden expects a value
       (and (not oe) (retval-conform? (cycle-retval oracle) gr)))
      (else                                         ; output-only
       (and (not oe) (string=? (norm (cycle-output oracle)) (norm go)))))))

;; ---- run the suite -------------------------------------------------------------

;; Per-file subprocess timeout (seconds): a cross-family oracle has no eval-cycle
;; timeout, and a cycle that blocks on (read) would otherwise consume the spec stream
;; and hang.  On timeout the file's unfinished cycles parse as error cycles.
(define conf-timeout
  (let ((e (get-environment-variable "CONF_TIMEOUT")))
    (or (and e (string->number e)) 20)))

(define oracle (make-sibling-interp conf-name 'oracle
                                    (list conf-exe "-I" conf-lib) conf-driver
                                    conf-timeout))
(define golden (make-log-playback "golden"))

(define (log-file? name)
  (let ((n (string-length name)))
    (and (>= n 4) (string=? (substring name (- n 4) n) ".log"))))
(define (path-join d f) (string-append d "/" f))
(define (first-line s)
  (let ((n (string-length s)))
    (let loop ((i 0))
      (cond ((>= i n) s) ((char=? (string-ref s i) #\newline) (substring s 0 i))
            (else (loop (+ i 1)))))))

(define files
  (let loop ((names (directory-files suite-dir)) (acc '()))
    (cond ((null? names) (reverse acc))
          ((log-file? (car names)) (loop (cdr names) (cons (car names) acc)))
          (else (loop (cdr names) acc)))))

(define total 0)
(define agree 0)
(define disagrees '())          ; (file input golden-channel oracle-cycle)

(for-each
 (lambda (name)
   (let* ((items (log-source (path-join suite-dir name)))
          (verdicts (differ-run items (list golden oracle)
                                'reference cycle-conformance-match?)))
     (for-each
      (lambda (v)
        (set! total (+ total 1))
        (if (verdict-agree? v)
            (set! agree (+ agree 1))
            (let* ((entry (verdict-item v))
                   (oc (let ((p (assoc conf-name (verdict-results v)))) (and p (cdr p)))))
              (set! disagrees
                    (cons (list name (first-line (entry-input entry))
                                (entry-retval entry) (entry-error entry) (entry-output entry)
                                oc)
                          disagrees)))))
      verdicts)))
 files)

(set! disagrees (reverse disagrees))
(for-each
 (lambda (d)
   (display "  ") (display (list-ref d 0)) (display ":  ") (display (list-ref d 1)) (newline)
   (let ((gr (list-ref d 2)) (ge (list-ref d 3)) (go (list-ref d 4)) (oc (list-ref d 5)))
     (cond ((> (string-length ge) 0) (display "       golden: error [") (display ge) (display "]"))
           ((> (string-length gr) 0) (display "       golden: ==> [") (display gr) (display "]"))
           (else (display "       golden: out [") (display go) (display "]")))
     (newline)
     (display "       ") (display conf-name) (display ": ") (display (cycle->string oc)) (newline)))
 disagrees)

(newline)
(display "=== conformance: golden vs ") (display conf-name) (display " (") (display suite-dir) (display ") ===") (newline)
(display "cycles=") (display total) (display "  agree=") (display agree)
(display "  disagree=") (display (length disagrees)) (newline)
(display "  (disagreements are cross-implementation differences for review, not failures)") (newline)
(exit 0)
