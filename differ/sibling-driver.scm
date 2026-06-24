;;; sibling-driver.scm -- subprocess driver for the differ's sibling runner (inc 3b).
;;;
;;; Run by another interpreter (the sibling port) as a child process.  Reads, from
;;; stdin, one (input-string fold-case?) form per source entry (written by the parent
;;; with `write`, so strings are properly escaped); runs each through the SAME
;;; eval-cycle path the in-process host runner uses, in ONE make-toplevel-environment
;;; so state persists across cycles; and writes, to stdout, one
;;; (output retval error timed-out?) form per cycle (again with `write`, so the parent
;;; reads them back unambiguously).  eval-cycle captures the test's own output into
;;; `output`, so stdout carries ONLY these result forms -- no REPL chrome.
;;;
;;; Requires the eval-cycle primitive (both ports have it); it is NOT for cross-family
;;; interpreters like chibi (which lack it).
;;;
;;; Unlike the IN-PROCESS host runner -- which must isolate from the differ's own
;;; global via make-toplevel-environment -- this driver runs in a DEDICATED fresh
;;; process per source, so it uses the REAL (interaction-environment).  That gives
;;; full rawEval-grade fidelity for define-library / import / define-syntax (imported
;;; macros the expander only resolves in the actual global), which an isolated env
;;; does not; per-source isolation comes from the fresh process, cross-cycle state
;;; from the shared interaction-environment.

(import (scheme base) (scheme write) (scheme read) (scheme repl))

;; A test that calls (read) would otherwise steal from THIS driver's stdin spec stream
;; and corrupt every following cycle; rebind current-input-port to an empty port during
;; each eval so such a (read) yields eof (mirrors chibi-driver.scm).

;; These two live in the SAME (interaction-environment) the test cycles evaluate in, so
;; a test's own top-level define would clobber them; the %-bracketed names make a
;; collision practically impossible (6.04 defines `env`, which is why a plain `env`
;; broke -- the next eval-cycle got a list, not an environment).
(define %sd-timeout% 120)   ; seconds; matches the in-process host runner
(define %sd-env% (interaction-environment))
;; ONE empty input port, reused every cycle: a test that does (read) gets eof (so it
;; can't steal the spec stream), AND because it is the SAME object each cycle a test's
;; (eq? (current-input-port) saved-in) stays #t across cycles, matching the runner's
;; stable current-input-port.  (A fresh port per cycle broke 6.13.1's port-identity.)
(define %sd-empty-in% (open-input-string ""))

;; Mirror the .log runner, which binds %MAX_TCO_ITER_COUNT% in EVERY file's fresh env
;; (Listener.cpp:1310) so 3.05's proper-tail-recursion soak loops can size themselves;
;; harmless in suites that don't reference it.  This is env SETUP (like the runner's
;; per-file eval), not a test cycle.  Small count: the soak goldens are count-
;; independent and the battery is a self-consistency check, not a memory soak.
(eval-cycle "(define %MAX_TCO_ITER_COUNT% 1000)" %sd-env% %sd-timeout%)

(let loop ()
  (let ((spec (read)))
    (unless (eof-object? spec)
      (let* ((input (car spec))
             (fc    (cadr spec))
             (src   (if fc (string-append "#!fold-case\n" input) input)))
        (call-with-values
          (lambda ()
            (parameterize ((current-input-port %sd-empty-in%))
              (eval-cycle src %sd-env% %sd-timeout%)))
          (lambda (out ret err to)
            (write (list out ret err to))
            (newline))))
      (loop))))
