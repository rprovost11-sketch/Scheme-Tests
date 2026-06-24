;;; differ-battery.scm -- run a .log golden suite through the universal differ
;;; (increment 5).  This is the golden battery expressed as differ(reference = .log
;;; golden, subject = this port's live in-process host, compare = the .log match
;;; semantics) -- the same engine that powers the cross-port and sibling differs,
;;; pointed at the authoritative golden files.
;;;
;;; It runs ALONGSIDE the listener's own .log runner (which is NOT dismantled); its
;;; job is to reproduce the golden-battery verdict through the differ, proving the
;;; engine faithful and opening the door to cross-implementation variants (chibi/Chez)
;;; for free.  Per file it prints a pass/fail line like the real runner and exits
;;; nonzero if any cycle fails to match its golden.
;;;
;;; FAITHFULNESS depends on two launch conditions the real runner also establishes:
;;;   * --no-rc   -- a pristine global (no ~/.pyschemerc / ~/.cppscheme2rc), so
;;;                  rc defines never shadow a golden that expects a name unbound.
;;;   * cwd = the suite directory -- so a cycle's relative file path (file-exists?,
;;;                  include-library-declarations, ...) resolves exactly as the
;;;                  runner's per-file chdir makes it.
;;; The `]suites differ-feature` entry sets both.  To run it by hand, do the same --
;;; launch from the suite dir with --no-rc (DIFFER_HOME/DIFFER_SUITE default correctly
;;; for a log-tests/<suite> cwd):
;;;   cd scheme-tests/log-tests/feature-tests
;;;   <interp> --no-rc ../../differ/differ-battery.scm
;;; To point at another suite, override DIFFER_SUITE (and keep cwd = that suite dir so
;;; relative-path cycles resolve):
;;;   cd scheme-tests/log-tests/regression-tests
;;;   <interp> --no-rc ../../differ/differ-battery.scm

(import (scheme base) (scheme write) (scheme file) (scheme process-context)
        (scheme read) (scheme time))

;; DIFFER_HOME locates differ.scm; default is the differ dir as seen from a suite cwd
;; (log-tests/<suite> is two levels under scheme-tests, same as differ).  DIFFER_SUITE
;; is the directory of .log files; default "." = the cwd the launcher chdir'd into.
(define differ-home (or (get-environment-variable "DIFFER_HOME") "../../differ"))
(load (string-append differ-home "/differ.scm"))
(define suite-dir (or (get-environment-variable "DIFFER_SUITE") "."))

(define (log-file? name)
  (let ((n (string-length name)))
    (and (>= n 4) (string=? (substring name (- n 4) n) ".log"))))

(define (path-join d f) (string-append d "/" f))

;; reference = the .log golden (replays recorded channels, honouring ==> X or ==> Y /
;; %%% * / %any-error% / %optional-error%); subject = this port's live host runner.
(define golden    (make-log-playback "golden"))
;; The .log runner binds %MAX_TCO_ITER_COUNT% in EVERY file's fresh env (Listener.cpp:
;; 1310) so 3.05's proper-tail-recursion soak loops can size themselves; harmless in
;; suites that don't reference it.  Seed the host env the same way so the compliance
;; battery doesn't hit an unbound variable.  We use a SMALL count (not the runner's
;; 100000): the soak goldens return count-independent values (`done` / `#t` -- both
;; sides of every comparison use the same N), and this battery is a SELF-CONSISTENCY
;; check (golden and host are the SAME port, so they agree at any count) rather than a
;; memory soak -- the runner's `compliance-slow` variant owns the real high-N TCO
;; proof.  The small count keeps differ-compliance fast enough to live in `]suites all`.
(define host-of   (make-host-interp "host" 'host
                                    (list "(define %MAX_TCO_ITER_COUNT% 1000)")))

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
              (gold  (assoc-cdr "golden" (verdict-results v)))
              (act   (assoc-cdr "host"   (verdict-results v)))
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
          ;; reference mode: golden is the oracle, host must match it per cycle.
          (verdicts (differ-run items (list golden host-of)
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
