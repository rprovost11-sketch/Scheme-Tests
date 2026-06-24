;;; differ-battery.scm -- golden battery via the differ, IN-PROCESS HOST subject.
;;;
;;; The golden battery expressed as differ(reference = .log golden, subject = this
;;; port's live in-process host [eval-cycle in a fresh make-toplevel-environment per
;;; file], compare = the .log match semantics) -- the same engine that powers the
;;; cross-port and sibling differs, pointed at the authoritative golden files.  Runs
;;; ALONGSIDE the listener's own .log runner (NOT a replacement), reproducing its
;;; verdict through the differ.  Wired as ]suites differ-feature / differ-regression.
;;;
;;; The shared battery logic lives in differ-battery-core.scm; this thin wrapper only
;;; selects the SUBJECT (the in-process host).  The compliance corpus needs a different
;;; subject -- see differ-compliance.scm, which uses the subprocess sibling.
;;;
;;; FAITHFULNESS depends on two launch conditions the real runner also establishes:
;;;   * --no-rc   -- a pristine global (no ~/.pyschemerc / ~/.cppscheme2rc).
;;;   * cwd = the suite directory -- so a cycle's relative file path resolves as the
;;;                  runner's per-file chdir makes it.
;;; The ]suites entries set both.  By hand (DIFFER_HOME/DIFFER_SUITE default correctly
;;; for a log-tests/<suite> cwd):
;;;   cd scheme-tests/log-tests/feature-tests
;;;   <interp> --no-rc ../../differ/differ-battery.scm

(import (scheme base) (scheme write) (scheme file) (scheme process-context)
        (scheme read) (scheme time))

;; DIFFER_HOME locates differ.scm + the core; default is the differ dir as seen from a
;; suite cwd (log-tests/<suite> is two levels under scheme-tests, same as differ).
(define differ-home (or (get-environment-variable "DIFFER_HOME") "../../differ"))
(load (string-append differ-home "/differ.scm"))

;; Subject = the in-process host.  The .log runner binds %MAX_TCO_ITER_COUNT% in EVERY
;; file's fresh env (Listener.cpp:1310) so 3.05's proper-tail-recursion soak loops can
;; size themselves; seed the host env the same way (harmless where unused).  A SMALL
;; count suffices: the soak goldens are count-independent and this is a self-consistency
;; check (golden and host are the SAME port), not a memory soak.
(define subject-of (make-host-interp "subject" 'host
                                     (list "(define %MAX_TCO_ITER_COUNT% 1000)")))

(load (string-append differ-home "/differ-battery-core.scm"))
