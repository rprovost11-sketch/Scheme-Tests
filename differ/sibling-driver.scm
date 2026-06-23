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

(define host-cycle-timeout 120)   ; seconds; matches the in-process host runner
(define env (interaction-environment))

(let loop ()
  (let ((spec (read)))
    (unless (eof-object? spec)
      (let* ((input (car spec))
             (fc    (cadr spec))
             (src   (if fc (string-append "#!fold-case\n" input) input)))
        (call-with-values
          (lambda () (eval-cycle src env host-cycle-timeout))
          (lambda (out ret err to)
            (write (list out ret err to))
            (newline))))
      (loop))))
