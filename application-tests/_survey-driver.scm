;; Port-agnostic survey driver.  Reads every top-level form of r7rs-tests.scm
;; and evaluates it in the interaction environment with a per-form guard, so one
;; aborting form logs "FORMERR" and the rest continue.  Runs IDENTICALLY on
;; pyscheme and cppscheme2 (this is the parity instrument).  Temporary tooling.
;;
;; Run from either interpreter with -L pointing at this directory, e.g.
;;   python -m pyscheme -L <dir> <dir>/_survey-driver.scm
;;   cppscheme2          -L <dir> <dir>/_survey-driver.scm
;; The first form of r7rs-tests.scm is its own (import ... (srfi 64)), which is
;; eval'd into the interaction environment, pulling in the harness + libraries.
(import (scheme base) (scheme read) (scheme write)
        (scheme eval) (scheme repl) (scheme file))

(define %ie (interaction-environment))
(define %port
  (open-input-file
    "D:/SWDEV/Languages/Lisp/scheme-tests/application-tests/r7rs-tests.scm"))
(define %errs 0)

(let %loop ()
  (let ((%form (read %port)))
    (if (eof-object? %form)
        (begin
          (display "=== FORMERRS: ") (display %errs) (display " ===") (newline))
        (begin
          (guard (%e (#t
                      (set! %errs (+ %errs 1))
                      (display "FORMERR: ")
                      (if (error-object? %e)
                          (display (error-object-message %e))
                          (write %e))
                      (newline)))
            (eval %form %ie))
          (%loop)))))
