;;; differ-compliance.scm -- golden battery via the differ, SUBPROCESS SIBLING subject.
;;;
;;; The R7RS compliance corpus exercises define-library / import / cross-cycle
;;; define-syntax macros.  The in-process host (differ-battery.scm) evaluates each cycle
;;; in an ISOLATED make-toplevel-environment, where the expander cannot resolve imported
;;; macros (it resolves them only in the interpreter's ACTUAL global) -- so those cycles
;;; diverge from the golden.  A fresh SUBPROCESS evaluating in the real
;;; (interaction-environment) has no such isolation, restoring full rawEval-grade
;;; fidelity.  So the compliance battery uses the SIBLING subject: one same-port
;;; subprocess per file, launched --no-rc (pristine global, matching the runner's
;;; per-file reboot), driven by sibling-driver.scm.  Reference stays the .log golden;
;;; everything else (suite iteration, .run report) is the shared core.
;;;
;;; Run from the suite dir with --no-rc (DIFFER_HOME/DIFFER_SUITE default correctly):
;;;   cd scheme-tests/log-tests/R7RS-Compliance-Tests
;;;   <interp> --no-rc ../../differ/differ-compliance.scm
;;; DIFFER_SIBLING_TIMEOUT (seconds, default 120) caps each per-file subprocess.
;;;
;;; RESULT: cppScheme2 reproduces the golden 6952/6952.  pyScheme is 6951/6952 -- the
;;; lone miss is `(string->utf8 "λ")`, which the py sibling returns double-encoded
;;; (#u8(195 142 194 187) instead of #u8(206 187)).  That is a pyScheme run-process/
;;; stdin UTF-8 round-trip bug on Windows (the non-ASCII spec byte stream is decoded
;;; with the locale codepage, not UTF-8) -- a transport bug in the port, NOT in the
;;; differ; cpp's transport is byte-correct.  Tracked as a separate port fix.

(import (scheme base) (scheme write) (scheme file) (scheme process-context)
        (scheme read) (scheme time))

(define differ-home (or (get-environment-variable "DIFFER_HOME") "../../differ"))
(load (string-append differ-home "/differ.scm"))

(define sibling-timeout
  (let ((e (get-environment-variable "DIFFER_SIBLING_TIMEOUT")))
    (or (and e (string->number e)) 120)))

;; Subject = a fresh SAME-PORT subprocess per file (interpreter-argv = how to relaunch
;; this port), launched --no-rc and driven by sibling-driver.scm, which evaluates each
;; cycle through eval-cycle in the real (interaction-environment).  The sibling-driver
;; seeds %MAX_TCO_ITER_COUNT% the same way the runner does.
(define subject-of
  (make-sibling-interp "subject" 'sibling
                       (append (interpreter-argv) (list "--no-rc"))
                       (string-append differ-home "/sibling-driver.scm")
                       sibling-timeout))

(load (string-append differ-home "/differ-battery-core.scm"))
