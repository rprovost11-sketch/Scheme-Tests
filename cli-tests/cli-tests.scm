;;; cli-tests.scm -- shell-free process-boundary tests for the interpreter CLI.
;;;
;;; Things the .log suites cannot test because they run INSIDE an already-launched
;;; interpreter: -e evaluation, banner suppression, stdin (read), argv rejection
;;; and exit codes, and the .run batch-report behavior.  Replaces the bash run.sh:
;;; it relaunches THIS interpreter via (interpreter-argv) + run-process, captures
;;; exit code and output directly, and asserts on them.  Depends only on the
;;; interpreter -> runs on Windows / Linux / macOS with no shell.
;;;
;;; The suite sets cwd to this directory (cli-tests/), so the committed fixture
;;; tests-root `runfix/` is reachable by the relative path the listener resolves.
;;;
;;; Run:  <interp> cli-tests.scm   (exits nonzero if any check fails)

(import (scheme base) (scheme file) (scheme write))

(define pass 0)
(define fail 0)
(define (ok msg) (set! pass (+ pass 1)) (display "  ok    ") (display msg) (newline))
(define (ng msg . extra)
  (set! fail (+ fail 1))
  (display "  FAIL  ") (display msg) (newline)
  (for-each (lambda (e) (display "          ") (display e) (newline)) extra))

;; Substring search (R7RS-small has no string-contains).
(define (contains? hay needle)
  (let ((hn (string-length hay)) (nn (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i nn) hn) #f)
            ((string=? (substring hay i (+ i nn)) needle) #t)
            (else (loop (+ i 1)))))))

(define (assert-contains msg out needle)
  (if (contains? out needle) (ok msg)
      (ng msg (string-append "expected output to contain: " needle)
              (string-append "got: " out))))
(define (assert-absent msg out needle)
  (if (contains? out needle)
      (ng msg (string-append "expected output NOT to contain: " needle)
              (string-append "got: " out))
      (ok msg)))
(define (assert-rc msg code expected)
  (if (= code expected) (ok msg)
      (ng msg (string-append "expected exit " (number->string expected)
                             ", got " (number->string code)))))

(define interp (interpreter-argv))

;; Launch the interpreter with EXTRA args and STDIN; return (values combined code),
;; where combined = stdout ++ stderr (mirrors run.sh's 2>&1).
(define (run-interp stdin extra-args)
  (call-with-values
    (lambda () (run-process (append interp extra-args) stdin))
    (lambda (code out err) (values (string-append out err) code))))

;; ---- -e / --evaluate ----------------------------------------------------
(call-with-values (lambda () (run-interp "" '("-e" "(+ 1 2)")))
  (lambda (out code)
    (assert-contains "eval: -e evaluates an expression and prints its value" out "==> 3")
    (assert-rc "eval: -e exits 0 on success" code 0)
    (assert-absent "eval: -e suppresses the startup banner" out "Welcome")))

(call-with-values (lambda () (run-interp "" '("-e" "(define x 5)" "-e" "x")))
  (lambda (out code)
    (assert-contains "eval: -e is repeatable and shares interpreter state" out "==> 5")))

;; ---- stdin (read) -------------------------------------------------------
(call-with-values (lambda () (run-interp "(1 2 3)\n" '("-e" "(read)")))
  (lambda (out code)
    (assert-contains "stdin: (read) reads a datum piped on stdin" out "==> (1 2 3)")))

(call-with-values (lambda () (run-interp "" '("-e" "(read)")))
  (lambda (out code)
    (assert-contains "stdin: (read) at EOF returns the eof object" out "#<eof>")))

;; ---- argv rejection / exit codes ----------------------------------------
(call-with-values (lambda () (run-interp "" '("-e" "(+ 1 2)" "some-target.scm")))
  (lambda (out code)
    (assert-rc "argv: -e combined with a file target exits 2" code 2)
    (assert-contains "argv: -e + target explains the conflict" out "cannot be combined")))

;; ---- .run report behavior -----------------------------------------------
;; runfix/ is a committed tests-root: two log suites, one with a planted failure.
;; Drive a listener session that points ]scheme-tests at it and runs both suites;
;; the combined report's path is printed as "Test output: <path>".
(define (read-file-string path)
  (call-with-port (open-input-file path)
    (lambda (p)
      (let loop ((acc '()))
        (let ((c (read-char p)))
          (if (eof-object? c)
              (list->string (reverse acc))
              (loop (cons c acc))))))))

;; Count non-overlapping occurrences of NEEDLE in S.
(define (count-substr needle s)
  (let ((hn (string-length s)) (nn (string-length needle)))
    (let loop ((i 0) (n 0))
      (cond ((> (+ i nn) hn) n)
            ((string=? (substring s i (+ i nn)) needle) (loop (+ i nn) (+ n 1)))
            (else (loop (+ i 1) n))))))

;; Text from just after MARKER up to the next CR/LF, or #f if MARKER is absent.
(define (line-after marker s)
  (let ((hn (string-length s)) (mn (string-length marker)))
    (let loop ((i 0))
      (cond ((> (+ i mn) hn) #f)
            ((string=? (substring s i (+ i mn)) marker)
             (let ((start (+ i mn)))
               (let scan ((j start))
                 (if (or (>= j hn)
                         (char=? (string-ref s j) #\newline)
                         (char=? (string-ref s j) #\return))
                     (substring s start j)
                     (scan (+ j 1))))))
            (else (loop (+ i 1)))))))

(call-with-values
  (lambda () (run-process interp
              (string-append "]scheme-tests runfix\n"
                             "]suites feature regression\n"
                             "]quit\n")))
  (lambda (code out err)
    (let* ((combined (string-append out err))
           (runpath (line-after "Test output: " combined)))
      ;; Exactly one combined report per ]suites batch (one "Test output:" line),
      ;; not one per suite -- tests the same property as counting runs/*.run files,
      ;; without needing a directory-listing primitive.
      (let ((nrep (count-substr "Test output: " combined)))
        (if (= nrep 1)
            (ok ".run: ]suites over two suites writes exactly one combined report")
            (ng ".run: one combined report per ]suites"
                (string-append "expected 1 'Test output:' line, found "
                               (number->string nrep)))))
      (if (not runpath)
          (ng ".run: ]suites over two suites writes one combined report"
              "no 'Test output:' line in listener output" combined)
          (let ((report (read-file-string runpath)))
            (assert-contains ".run: combined report has the feature section"    report "suite: feature")
            (assert-contains ".run: combined report has the regression section" report "suite: regression")
            (assert-contains ".run: failing case is recorded with its expression" report "(* 6 7)")
            (assert-contains ".run: failing case shows expected vs actual return" report "expected return: [999]")
            (assert-absent   ".run: passing feature case detail omitted (failure-only)"    report "(+ 1 2)")
            (assert-absent   ".run: passing regression case detail omitted (failure-only)" report "(list 1 2)"))))))

(newline)
(display "cli-tests: ") (display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(exit (if (= fail 0) 0 1))
