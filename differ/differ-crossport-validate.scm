;;; differ-crossport-validate.scm -- cross-PORT sibling demo (increment 3b follow-on).
;;;
;;; The payoff of having BOTH live runners: compare ONE port IN-PROCESS (the host,
;;; via eval-cycle) against the OTHER port as a SUBPROCESS sibling (driven by
;;; sibling-driver.scm), peer / strict, over a whole .log suite.  The host is
;;; whichever port runs this script; the sibling is the other port, launched from its
;;; own exe argv -- exactly the cross-IMPLEMENTATION shape the engine was built for,
;;; but with one side in-process and one side a subprocess.
;;;
;;; Because the two ports are mirror implementations they should agree on every cycle.
;;; The ONE known exception is environment pollution from ~/.pyschemerc, which defines
;;; fold-left/fold-right/pp/...: cppScheme2 has no rc file, so any cycle that expects
;;; one of those names UNBOUND diverges.  Those are a REAL, correctly-detected
;;; interpreter difference (rc state) -- the differ doing its job, not a port bug.
;;; They appear symmetrically whichever port is the host.
;;;
;;; Run with cwd = this directory.  For the py sibling to launch from a cpp host, set
;;; PYTHONPATH so the subprocess inherits it (cpp ignores it, the py child needs it):
;;;   cpp host:  PYTHONPATH=<3PyScheme> cppscheme2.exe        differ-crossport-validate.scm
;;;   py  host:  PYTHONPATH=<3PyScheme> python -m pyscheme    differ-crossport-validate.scm
;;; Exits 0 iff host == sibling on every cycle.

(import (scheme base) (scheme write) (scheme file) (scheme process-context) (scheme read))

(define differ-home (or (get-environment-variable "DIFFER_HOME") "."))
(load (string-append differ-home "/differ.scm"))
(define driver-path (string-append differ-home "/sibling-driver.scm"))

(define suite-dir
  (or (get-environment-variable "DIFFER_SUITE") "../log-tests/feature-tests"))

;; The other port's launcher.  cpp = a known relative exe path (cwd = this dir, two
;; levels under Lisp/, same as cross-port-common.scm); py = `python -m pyscheme`
;; relying on PYTHONPATH in the environment.  Both overridable for other layouts.
(define cpp-exe
  (or (get-environment-variable "CPP_EXE") "../../4CPPScheme2/build/Release/cppscheme2.exe"))
(define py-launch
  (list (or (get-environment-variable "PY_EXE") "python") "-m" "pyscheme"))

(define (string-suffix? suf s)
  (let ((ls (string-length s)) (lu (string-length suf)))
    (and (>= ls lu) (string=? (substring s (- ls lu) ls) suf))))

;; Which port am I?  Pick the OTHER as the subprocess sibling.
(define my-argv (interpreter-argv))
(define host-is-cpp? (string-suffix? "cppscheme2.exe" (car my-argv)))
(define host-name    (if host-is-cpp? "cpp-host" "py-host"))
(define sibling-name (if host-is-cpp? "py-sibling" "cpp-sibling"))
(define sibling-argv (if host-is-cpp? py-launch (list cpp-exe)))

(define host-of    (make-host-interp host-name 'host))
(define sibling-of (make-sibling-interp sibling-name 'sibling sibling-argv driver-path))

;; STRICT (default): out+retval+error-text all byte-equal -- the right bar for mirror
;; ports, but it also surfaces OS/codec error-MESSAGE tails that even the golden marks
;; as varying.  COARSE (DIFFER_STRICT=0): out + errored-or-not only -- drops those
;; cosmetic error-wording differences, isolating genuine behavioural divergence (e.g.
;; the ~/.pyschemerc fold-left pollution).
(define strict? (not (equal? (get-environment-variable "DIFFER_STRICT") "0")))
(define compare (if strict? cycle-strict=? cycle-coarse=?))

(define (log-file? name)
  (let ((n (string-length name)))
    (and (>= n 4) (string=? (substring name (- n 4) n) ".log"))))

(define (path-join d f) (string-append d "/" f))

(display "=== cross-port: ") (display host-name) (display " (in-process) vs ")
(display sibling-name) (display " (subprocess) ===") (newline)
(display "sibling launch: ") (write sibling-argv)
(display "  compare: ") (display (if strict? "strict" "coarse")) (newline)
(newline)

(define total-cycles 0)
(define total-diverged 0)
(define files-diverged 0)

(for-each
 (lambda (name)
   (when (log-file? name)
     (let* ((items (log-source (path-join suite-dir name)))
            (verdicts (differ-run items (list host-of sibling-of)
                                  'peer compare))
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
(display "=== ") (display host-name) (display " (in-process) vs ")
(display sibling-name) (display " (subprocess), peer strict ===") (newline)
(display "cycles=") (display total-cycles)
(display "  diverged=") (display total-diverged)
(display "  files-with-divergence=") (display files-diverged) (newline)
(exit (if (= total-diverged 0) 0 1))
