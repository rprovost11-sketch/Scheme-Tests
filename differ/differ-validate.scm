;;; differ-validate.scm -- validate the live HOST runner against a real golden suite.
;;;
;;; Runs the differ in REFERENCE mode (reference = the .log golden via playback;
;;; subject = the live host port via eval-cycle) across every .log file in a
;;; directory, and tallies divergences.  Zero divergences = the in-process host
;;; runner reproduces the golden battery faithfully (output, return value, AND error
;;; text incl. class + line/col).  This is the increment-3 fidelity proof and a
;;; preview of running the battery through the differ (increment 5).
;;;
;;; Run with cwd = this directory:
;;;   <interp> differ-validate.scm
;;; Set DIFFER_SUITE to point at another suite dir; default ../log-tests/feature-tests.
;;; Exits 0 iff all agree.

(import (scheme base) (scheme write) (scheme file) (scheme process-context))
(load "differ.scm")

(define suite-dir
  (or (get-environment-variable "DIFFER_SUITE") "../log-tests/feature-tests"))

(define (log-file? name)
  (let ((n (string-length name)))
    (and (>= n 4) (string=? (substring name (- n 4) n) ".log"))))

(define (path-join d f) (string-append d "/" f))

(define golden-of (make-log-playback "golden"))
(define host-of   (make-host-interp "host-live" 'host))

(define total-cycles 0)
(define total-diverged 0)
(define files-diverged 0)

(for-each
 (lambda (name)
   (when (log-file? name)
     (let* ((path (path-join suite-dir name))
            (items (log-source path))
            (verdicts (differ-run items (list golden-of host-of)
                                  'reference cycle-golden-match?))
            (n  (length verdicts))
            (nd (d-count (lambda (v) (not (verdict-agree? v))) verdicts)))
       (set! total-cycles (+ total-cycles n))
       (set! total-diverged (+ total-diverged nd))
       (when (> nd 0)
         (set! files-diverged (+ files-diverged 1))
         (display "--- ") (display name) (display ": ")
         (display nd) (display " of ") (display n) (display " diverged ---") (newline)
         (differ-report verdicts 'reference)))))
 (directory-files suite-dir))

(newline)
(display "=== host-runner validation vs golden (") (display suite-dir) (display ") ===")
(newline)
(display "cycles=") (display total-cycles)
(display "  diverged=") (display total-diverged)
(display "  files-with-divergence=") (display files-diverged) (newline)
(exit (if (= total-diverged 0) 0 1))
