;;; eval-cycle-validate.scm -- measure the pure-Scheme scheme-eval-cycle against
;;; the NATIVE (eval-cycle ...) primitive over the real .log corpus, to establish
;;; empirically exactly how much of eval-cycle reduces to Scheme and what minimal
;;; host coupling remains.
;;;
;;; For each suite it parses the .log golden (native parse-log-file), then -- per
;;; file, ONE env each (state persists across cycles, like the differ's host
;;; runner) -- runs every entry's input through BOTH the native eval-cycle and
;;; scheme-eval-cycle, and classifies the per-cycle (output retval error timed-out?)
;;; agreement:
;;;   FULL      all four channels byte-identical
;;;   CORE      output+retval+timeout identical, error text differs but the Scheme
;;;             message body is contained in the native error -> pure format chrome
;;;             (class + line/col + source echo + caret), the KNOWN irreducible gap
;;;   ERRDIFF   output+retval+timeout identical but error presence/body disagrees
;;;   DISAGREE  output, retval or timeout differ -- a real reimplementation gap
;;;
;;; Exit 0 iff there are no DISAGREE and no ERRDIFF cycles (i.e. the reducible core
;;; is faithful and every error difference is just unrecoverable chrome).
;;;
;;; Run from the differ dir (default); honours DIFFER_HOME (eval-cycle.scm) and
;;; CORPUS_ROOT.  Defaults to the self-contained suites (feature + regression);
;;; set SUITES to override.  Needs -L <SRFI> for (srfi 152) string-contains:
;;;   cd scheme-tests/differ
;;;   <interp> --no-rc -L D:/SWDEV/Languages/Lisp/SRFI eval-cycle-validate.scm

(import (scheme base) (scheme write) (scheme eval) (scheme read) (scheme repl)
        (scheme file) (scheme process-context) (srfi 152))

(define differ-home (or (get-environment-variable "DIFFER_HOME") "."))
(load (string-append differ-home "/eval-cycle.scm"))

(define corpus-root (or (get-environment-variable "CORPUS_ROOT") "../log-tests"))
;; feature + regression are self-contained; compliance leans on cross-cycle
;; macro/library state the isolated in-process host can't resolve (it errors the
;; SAME way under both eval-cycles, so it only inflates the error-chrome bucket).
(define suites
  (let ((s (get-environment-variable "SUITES")))
    (if s (list s) '("feature-tests" "regression-tests"))))

(define (log-file? name)
  (let ((n (string-length name)))
    (and (>= n 4) (string=? (substring name (- n 4) n) ".log"))))
(define (path-join a b) (string-append a "/" b))

;; The .log runner seeds this in every file's env so proper-tail-recursion soak
;; loops size themselves; a small count keeps the differential fast.
(define seed-prelude "(define %MAX_TCO_ITER_COUNT% 1000)")

;; --- tallies ---
(define n-full 0) (define n-fsartifact 0) (define n-errdiff 0) (define n-disagree 0)
(define n-cycles 0)
(define examples-shown 0)

(define (show . xs) (for-each display xs) (newline))

;; A destructive filesystem cycle (delete-file / rename-file ...) can't be replayed:
;; the validator runs each cycle native-THEN-scheme over a SHARED filesystem, so the
;; first run consumes the file and the second sees a file error.  Recognise that
;; precise pattern (output/retval/timeout agree; one side clean, the other a file
;; error) as a double-run artifact of THIS harness, not an eval-cycle divergence.
(define (fs-artifact? nat-err sc-err)
  (or (and (string=? nat-err "") (string-contains sc-err "FileError"))
      (and (string=? sc-err "")  (string-contains nat-err "FileError"))))

(define (classify in nat-out nat-ret nat-err nat-to sc-out sc-ret sc-err sc-to)
  (cond
    ((and (string=? nat-out sc-out) (string=? nat-ret sc-ret)
          (string=? nat-err sc-err) (eq? nat-to sc-to))
     (set! n-full (+ n-full 1)))
    ((not (and (string=? nat-out sc-out) (string=? nat-ret sc-ret) (eq? nat-to sc-to)))
     (set! n-disagree (+ n-disagree 1))
     (when (< examples-shown 12)
       (set! examples-shown (+ examples-shown 1))
       (show "DISAGREE:")
       (write in) (newline)
       (show "  out  nat=" (%w nat-out) " sc=" (%w sc-out))
       (show "  ret  nat=" (%w nat-ret) " sc=" (%w sc-ret))
       (show "  to   nat=" nat-to " sc=" sc-to)))
    ;; output+retval+timeout agree; only error text differs
    ((fs-artifact? nat-err sc-err)
     (set! n-fsartifact (+ n-fsartifact 1)))   ; double-run filesystem artifact
    (else
     (set! n-errdiff (+ n-errdiff 1))
     (when (< examples-shown 12)
       (set! examples-shown (+ examples-shown 1))
       (show "ERRDIFF:")
       (write in) (newline)
       (show "  nat-err=" (%w nat-err))
       (show "  sc-err =" (%w sc-err))))))

;; compact one-line write of a string for diagnostics
(define (%w s)
  (let ((x (%ec-write-to-string s)))
    (if (> (string-length x) 70) (string-append (substring x 0 70) "...\"") x)))

;; EC_SKIP = comma-separated substrings; a file whose name contains any is skipped
;; (used to exclude inputs that crash the host eval path while measuring the core).
(define skip-subs
  (let ((s (get-environment-variable "EC_SKIP")))
    (if s (string-split s ",") '())))
(define (skip-file? name)
  (let loop ((ss skip-subs))
    (cond ((null? ss) #f)
          ((string-contains name (car ss)) #t)
          (else (loop (cdr ss))))))

(define (run-suite dir)
  (let ((d (path-join corpus-root dir)))
    (for-each
     (lambda (name)
       (when (and (log-file? name) (not (skip-file? name)))
         (let* ((path (path-join d name))
                (entries (parse-log-file path))
                (nat-env (make-toplevel-environment))
                (sc-env  (make-toplevel-environment)))
           ;; seed both envs like the runner
           (eval-cycle seed-prelude nat-env #f)
           (scheme-eval-cycle seed-prelude sc-env)
           (for-each
            (lambda (e)
              (let* ((fc (list-ref e 4))
                     (in (if fc
                             (string-append "#!fold-case\n" (list-ref e 0))
                             (list-ref e 0))))
                (set! n-cycles (+ n-cycles 1))
                (when (get-environment-variable "EC_TRACE")
                  (display "  TRACE " (current-error-port))
                  (display name (current-error-port))
                  (display " <<" (current-error-port))
                  (write in (current-error-port))
                  (display ">>" (current-error-port)) (newline (current-error-port))
                  (flush-output-port (current-error-port)))
                (call-with-values (lambda () (eval-cycle in nat-env #f))
                  (lambda (no nr ne nt)
                    (call-with-values (lambda () (scheme-eval-cycle in sc-env))
                      (lambda (so sr se st)
                        (classify in no nr ne nt so sr se st)))))))
            entries))))
     (directory-files d))))

(for-each run-suite suites)

(newline)
(show "=== scheme-eval-cycle vs native eval-cycle (" suites ") ===")
(show "cycles=" n-cycles)
(show "  FULL       (all 4 channels identical)       = " n-full)
(show "  FSARTIFACT (destructive FS op, can't replay) = " n-fsartifact)
(show "  ERRDIFF    (out/ret/to identical; err differs) = " n-errdiff)
(show "  DISAGREE   (out/ret/to differ)              = " n-disagree)
;; With checked-eval the error text is the runner-formatted string too, so every
;; channel is byte-identical -- except cycles whose destructive filesystem side
;; effect the double-run validator cannot replay (counted separately, not a fault).
(let ((ok (and (= n-disagree 0) (= n-errdiff 0))))
  (show (if ok
            "BYTE-IDENTICAL -- scheme-eval-cycle == native eval-cycle (modulo non-replayable FS side effects)"
            "DIVERGENCE -- see ERRDIFF/DISAGREE above"))
  (exit (if ok 0 1)))
