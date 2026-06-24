;;; differ-battery-core.scm -- shared body of the golden-battery differ.
;;;
;;; Loaded (via `load`) by a thin wrapper that has ALREADY (import ...)ed, loaded
;;; differ.scm, and defined `subject-of` (the <interp> under test, named "subject"):
;;;   * differ-battery.scm    -- subject = the in-process HOST (feature / regression)
;;;   * differ-compliance.scm -- subject = a subprocess SIBLING (real interaction-
;;;                              environment, full macro fidelity for the compliance
;;;                              corpus's define-library / import / define-syntax)
;;; The reference is always the .log golden.  This file owns everything common: the
;;; suite iteration, the .log match comparison, and the runner-format .run report.

(define suite-dir (or (get-environment-variable "DIFFER_SUITE") "."))
(define golden    (make-log-playback "golden"))

(define (log-file? name)
  (let ((n (string-length name)))
    (and (>= n 4) (string=? (substring name (- n 4) n) ".log"))))

(define (path-join d f) (string-append d "/" f))

;; ---- .run artifact identity -----------------------------------------------------
;; The failure report is written to a runs/ dir like the listener runner's, but the
;; filename is STAMPED with the interpreter name AND version so a stored .run can be
;; cross-referenced to the exact build that produced it.  NAME comes from
;; interpreter-argv (the same probe the cross-port differ uses); VERSION from the
;; interpreter-version primitive; the leading epoch-seconds keeps successive runs
;; distinct.  Output dir defaults to runs/ under the cwd (globally gitignored in
;; scheme-tests), overridable via DIFFER_RUNS_DIR.  No new CLI arg -- config stays on
;; the env-var channel the differ already uses (DIFFER_HOME/DIFFER_SUITE/...).
(define (string-suffix? suf s)
  (let ((ls (string-length s)) (lu (string-length suf)))
    (and (>= ls lu) (string=? (substring s (- ls lu) ls) suf))))
;; NB: named this-interp-* to avoid shadowing differ.scm's <interp> record accessor
;; `interp-name`, which the core applies as a procedure.
(define this-interp-name
  (if (string-suffix? "cppscheme2.exe" (car (interpreter-argv))) "CPPScheme2" "PyScheme"))
(define this-interp-ver (interpreter-version))
(define runs-dir    (or (get-environment-variable "DIFFER_RUNS_DIR") "runs"))
(define run-path
  (string-append runs-dir "/"
                 (number->string (exact (round (current-second))))
                 "-differ-" this-interp-name "-" this-interp-ver ".run"))
(create-directory runs-dir)
(define run-port (open-output-file run-path))

;; One-time header documenting the run; per-file failure detail is appended below.
(parameterize ((current-output-port run-port))
  (display "=== differ golden battery .run report ===") (newline)
  (display "suite:       ") (display suite-dir) (newline)
  (display "interpreter: ") (display this-interp-name) (display " ") (display this-interp-ver) (newline)
  (display "(failure-only detail follows; stdout carries the full pass/fail summary)")
  (newline))

;; ---- .run-style per-channel failure report ------------------------------------
;; Mirrors the listener runner's failure-only report (Listener sessionLog_test): a
;; file header, then for each diverging cycle the input label and ONLY the channels
;; that differ -- decided per-channel by log-match-detail (the increment-5 primitive)
;; so output / return / error are reported independently, exactly like the runner --
;; then an "N of M FAILED" footer.

(define (assoc-cdr name alist)
  (let ((p (assoc name alist))) (and p (cdr p))))

(define (run-first-line s)                     ; first line of S
  (let ((n (string-length s)))
    (let loop ((i 0))
      (cond ((>= i n) s)
            ((char=? (string-ref s i) #\newline) (substring s 0 i))
            (else (loop (+ i 1)))))))

(define (run-strip s)                          ; trim leading/trailing whitespace
  (define (ws? c) (or (char=? c #\space) (char=? c #\tab)
                      (char=? c #\newline) (char=? c #\return)))
  (let ((n (string-length s)))
    (let start ((a 0))
      (cond ((and (< a n) (ws? (string-ref s a))) (start (+ a 1)))
            (else (let end ((b n))
                    (if (and (> b a) (ws? (string-ref s (- b 1))))
                        (end (- b 1))
                        (substring s a b))))))))

(define (run-label input)                      ; runner's label: first line, capped
  (let ((l (run-first-line (run-strip input))))
    (if (> (string-length l) 56)
        (string-append (substring l 0 53) "...")
        l)))

(define (str-prefix? pre s)
  (let ((lp (string-length pre)) (ls (string-length s)))
    (and (>= ls lp) (string=? (substring s 0 lp) pre))))

(define (any-error-pattern? e)                 ; golden error means "any error"
  (or (string=? e "*") (str-prefix? "%any-error%" e)))

(define (pad3 n)                               ; right-align like the runner's %3d
  (let ((s (number->string n)))
    (string-append (make-string (max 0 (- 3 (string-length s))) #\space) s)))

(define (make-dashes k) (make-string k #\-))

(define (kv label val)
  (display "         ") (display label) (display " [") (display val) (display "]") (newline))

;; Emit the .run report for ONE file's verdicts (called only when it has failures).
(define (emit-run-report path verdicts)
  (newline)
  (display "Test file: ") (display path) (newline)
  (display (make-dashes (+ 11 (string-length path)))) (newline)
  (for-each
   (lambda (v)
     (unless (verdict-agree? v)
       (let* ((entry (verdict-item v))
              (gold  (assoc-cdr "golden"  (verdict-results v)))
              (act   (assoc-cdr "subject" (verdict-results v)))
              (detail (log-match-detail
                       (cycle-output gold) (cycle-retval gold) (cycle-error gold)
                       (cycle-output act)  (cycle-retval act)  (cycle-error act)
                       (cycle-timed-out act))))
         (display "  ") (display (pad3 (+ 1 (verdict-index v)))) (display ". FAIL  ")
         (display (run-label (entry-input entry))) (newline)
         (when (cycle-timed-out act)
           (display "         *** evaluation timed out (treated as failure) ***") (newline))
         (unless (list-ref detail 1)            ; retval channel
           (kv "expected return:" (cycle-retval gold))
           (kv "actual return:  " (cycle-retval act)))
         (unless (list-ref detail 0)            ; output channel
           (kv "expected output:" (cycle-output gold))
           (kv "actual output:  " (cycle-output act)))
         (unless (list-ref detail 2)            ; error channel
           (if (any-error-pattern? (cycle-error gold))
               (begin (display "         expected an error, but none was raised") (newline))
               (begin (kv "expected error: " (cycle-error gold))
                      (kv "actual error:   " (cycle-error act))))))))
   verdicts)
  (newline)
  (display (d-count (lambda (v) (not (verdict-agree? v))) verdicts))
  (display " of ") (display (length verdicts)) (display " FAILED") (newline))

(define total-cycles 0)
(define total-failed 0)
(define files-failed 0)

(define files
  (let loop ((names (directory-files suite-dir)) (acc '()))
    (cond ((null? names) (reverse acc))
          ((log-file? (car names)) (loop (cdr names) (cons (car names) acc)))
          (else (loop (cdr names) acc)))))

(for-each
 (lambda (name)
   (let* ((items (log-source (path-join suite-dir name)))
          ;; reference mode: golden is the oracle, the subject must match it per cycle.
          (verdicts (differ-run items (list golden subject-of)
                                'reference cycle-golden-match?))
          (n  (length verdicts))
          (nf (d-count (lambda (v) (not (verdict-agree? v))) verdicts)))
     (set! total-cycles (+ total-cycles n))
     (set! total-failed (+ total-failed nf))
     (display "  ") (display name)
     (let ((pad (- 52 (string-length name))))
       (let loop ((k pad)) (when (> k 0) (display " ") (loop (- k 1)))))
     (if (= nf 0)
         (begin (display n) (display " passed"))
         (begin (set! files-failed (+ files-failed 1))
                (display nf) (display " of ") (display n) (display " FAILED")))
     (newline)
     (when (> nf 0)
       (parameterize ((current-output-port run-port))
         (emit-run-report (path-join suite-dir name) verdicts)))))
 files)

;; The grand-total summary goes to BOTH the .run file and stdout (the file documents
;; the run; stdout is what ]suites surfaces).
(define (write-summary)
  (newline)
  (display "=== differ golden battery: ") (display suite-dir) (display " ===") (newline)
  (display "cycles=") (display total-cycles)
  (display "  failed=") (display total-failed)
  (display "  files-with-failure=") (display files-failed) (newline)
  (if (= total-failed 0)
      (begin (display "  ALL ") (display total-cycles) (display " CYCLES MATCHED THE GOLDEN") (newline))
      (begin (display "  *** ") (display total-failed) (display " CYCLE(S) DIVERGED FROM THE GOLDEN ***") (newline))))

(parameterize ((current-output-port run-port)) (write-summary))
(close-output-port run-port)
(write-summary)
(display "Test output: ") (display run-path) (newline)
(exit (if (= total-failed 0) 0 1))
