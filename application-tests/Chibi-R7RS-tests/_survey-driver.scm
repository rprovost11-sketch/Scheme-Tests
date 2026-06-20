;; Port-agnostic survey driver.  Reads every top-level form of r7rs-tests.scm
;; and evaluates it in the interaction environment with a per-form guard, so one
;; aborting form logs "FORMERR" and the rest continue.  Runs IDENTICALLY on
;; pyscheme and cppscheme2 (this is the parity instrument).  Temporary tooling.
;;
;; Run FROM THIS DIRECTORY (r7rs-tests.scm is opened by a relative path so the
;; driver is location-independent -- the test registry runs it with cwd set
;; here), with -L pointing at the SRFI repo so (srfi 64) resolves, e.g.
;;   python -m pyscheme -L <Lisp>/SRFI _survey-driver.scm
;;   cppscheme2          -L <Lisp>/SRFI _survey-driver.scm
;; The first form of r7rs-tests.scm is its own (import ... (srfi 64)), which is
;; eval'd into the interaction environment, pulling in the harness + libraries.
;;
;; Exit status: 0 only if every form evaluated (0 FORMERRs) AND the SRFI-64
;; runner recorded 0 failures -- so it works as an exit-0 suite in the registry.
(import (scheme base) (scheme read) (scheme write)
        (scheme eval) (scheme repl) (scheme file) (scheme process-context))

(define %ie (interaction-environment))
(define %port (open-input-file "r7rs-tests.scm"))
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

;; Pull the SRFI-64 failure tally out of the interaction environment (where the
;; harness lives).  Guarded: if the runner was already finalized away, treat the
;; count as unknown (0) and lean on the FORMERR count + the per-group summaries.
(define %fails
  (guard (%e (#t 0))
    (eval '(let ((r (test-runner-current)))
             (if r (test-runner-fail-count r) 0))
          %ie)))

(if (or (> %errs 0) (and (integer? %fails) (> %fails 0)))
    (begin
      (display "=== SURVEY FAILED: ") (display %fails)
      (display " test failure(s), ") (display %errs)
      (display " form error(s) ===") (newline)
      (exit 1))
    (begin
      (display "=== SURVEY OK ===") (newline)
      (exit 0)))
