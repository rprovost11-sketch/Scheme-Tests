;;; differ-subprocess-validate.scm -- validate the sibling SUBPROCESS runner (inc 3b).
;;;
;;; Peer-compares the in-process HOST runner against a SAME-PORT subprocess sibling
;;; (launched via interpreter-argv, driven by sibling-driver.scm) across a whole .log
;;; suite.  Both sides are the same port with the same rc/cwd, so they should agree on
;;; EVERY cycle -- any divergence is a fault in the subprocess mechanism (stdin
;;; serialisation, driver, result parsing), not a port or environment difference.
;;; Exits 0 iff host == sibling everywhere.
;;;
;;; Run with cwd = this directory (or set DIFFER_HOME):
;;;   <interp> differ-subprocess-validate.scm

(import (scheme base) (scheme write) (scheme file) (scheme process-context) (scheme read))

(define differ-home (or (get-environment-variable "DIFFER_HOME") "."))
(load (string-append differ-home "/differ.scm"))
(define driver-path (string-append differ-home "/sibling-driver.scm"))

(define suite-dir
  (or (get-environment-variable "DIFFER_SUITE") "../log-tests/feature-tests"))

(define (log-file? name)
  (let ((n (string-length name)))
    (and (>= n 4) (string=? (substring name (- n 4) n) ".log"))))

(define (path-join d f) (string-append d "/" f))

(define host-of    (make-host-interp "host" 'host))
(define sibling-of (make-sibling-interp "sibling" 'sibling (interpreter-argv) driver-path))

(define total-cycles 0)
(define total-diverged 0)
(define files-diverged 0)

(for-each
 (lambda (name)
   (when (log-file? name)
     (let* ((items (log-source (path-join suite-dir name)))
            (verdicts (differ-run items (list host-of sibling-of)
                                  'peer cycle-strict=?))
            (n  (length verdicts))
            (nd (d-count (lambda (v) (not (verdict-agree? v))) verdicts)))
       (set! total-cycles (+ total-cycles n))
       (set! total-diverged (+ total-diverged nd))
       (when (> nd 0)
         (set! files-diverged (+ files-diverged 1))
         (display "--- ") (display name) (display ": ")
         (display nd) (display " of ") (display n) (display " diverged ---") (newline)
         (differ-report verdicts 'peer)))))
 (directory-files suite-dir))

(newline)
(display "=== sibling subprocess vs in-process host (peer, same port) ===") (newline)
(display "cycles=") (display total-cycles)
(display "  diverged=") (display total-diverged)
(display "  files-with-divergence=") (display files-diverged) (newline)
(exit (if (= total-diverged 0) 0 1))
