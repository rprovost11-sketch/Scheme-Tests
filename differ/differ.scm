;;; differ.scm -- universal interpreter behaviour differ (CORE).  Increment 2.
;;;
;;; LOADED (not imported) after the loader's own (import (scheme base) ...),
;;; mirroring cross-port-tests/cross-port-common.scm.  Relies on (scheme base)
;;; plus the parse-log-file / log-match? extension primitives (increment 1).
;;;
;;; The CORE is deliberately TINY (user caution: "don't assign too much duty to
;;; the differ").  It runs each interpreter on each source item and classifies
;;; the per-item results under a caller-supplied COMPARE predicate.  Everything
;;; that varies -- per-cycle vs whole-program, strict vs coarse, peer vs
;;; reference, in-process vs subprocess -- lives in the interpreter DESCRIPTORS,
;;; the SOURCE, and the COMPARE predicate, never in the core.  The core never
;;; inspects a result; it only feeds pairs of results to compare.
;;;
;;; A .log file is one interpreter: parse-log-file yields the recorded
;;; {output,retval,error} per cycle and the log-playback run-fn replays them, so
;;; the existing golden battery becomes differ(reference=.log, subject=..., ...).
;;; See [[universal-interpreter-differ]].  Live execution runners arrive in
;;; increment 3; here interpreters are either .log playback or caller-supplied.

;; ---- small helpers (R7RS-small lacks filter) -----------------------------------

(define (d-filter pred lst)
  (cond ((null? lst) '())
        ((pred (car lst)) (cons (car lst) (d-filter pred (cdr lst))))
        (else (d-filter pred (cdr lst)))))

(define (d-count pred lst)
  (let loop ((l lst) (n 0))
    (cond ((null? l) n)
          ((pred (car l)) (loop (cdr l) (+ n 1)))
          (else (loop (cdr l) n)))))

(define (rstrip-nl s)                          ; drop trailing newlines
  (let loop ((i (string-length s)))
    (if (and (> i 0) (char=? (string-ref s (- i 1)) #\newline))
        (loop (- i 1))
        (substring s 0 i))))

;; ---- interpreter descriptor ----------------------------------------------------
;; run : (state item) -> result.  result is OPAQUE to the core; only compare reads it.
;; init : () -> state, called ONCE per differ-run (per source), so a live interpreter
;; can hold per-source state (e.g. a fresh environment) across the source's cycles.

(define-record-type <interp>
  (make-interp* name family init run run-source)
  interp?
  (name       interp-name)
  (family     interp-family)
  (init       interp-init)
  (run        interp-run)
  (run-source interp-run-source))   ; (items) -> list of results (item order), or #f

;; Stateless interpreter: RUN1 maps item -> result (no per-run state).  This is what
;; the .log playback and mock interpreters use; preserves the simple ctor signature.
(define (make-interp name family run1)
  (make-interp* name family (lambda () #f) (lambda (state item) (run1 item)) #f))

;; Stateful interpreter: INIT produces per-source state (once per differ-run, e.g. a
;; fresh make-environment); RUN maps (state item) -> result.
(define (make-stateful-interp name family init run)
  (make-interp* name family init run #f))

;; Batch interpreter: RUN-SRC maps the WHOLE item list -> a list of results (item
;; order, same length).  For runners that must process a source in one shot -- e.g. a
;; subprocess that takes all entries at once to amortise the spawn and keep state.
(define (make-source-interp name family run-src)
  (make-interp* name family
                (lambda () #f)
                (lambda (s i) (error "source-interp has no per-item run"))
                run-src))

;; ---- per-cycle result (one shape of result; the core never looks inside) -------

(define-record-type <cycle>
  (make-cycle output retval error timed-out)
  cycle?
  (output    cycle-output)
  (retval    cycle-retval)
  (error     cycle-error)
  (timed-out cycle-timed-out))

(define (cycle-errored? c) (> (string-length (cycle-error c)) 0))

(define (cycle->string c)
  (string-append "out=[" (cycle-output c) "] ret=[" (cycle-retval c)
                 "] err=[" (cycle-error c) "]"
                 (if (cycle-timed-out c) " <TIMEOUT>" "")))

;; ---- .log source + the .log file as a reference interpreter --------------------
;; An entry is the 5-element list (input output retval error fold-case?) that
;; parse-log-file returns.

(define (entry-input e)     (list-ref e 0))
(define (entry-output e)    (list-ref e 1))
(define (entry-retval e)    (list-ref e 2))
(define (entry-error e)     (list-ref e 3))
(define (entry-fold-case e) (list-ref e 4))

(define (log-source path) (parse-log-file path))   ; items = entries

;; Replay a .log entry's recorded channels as this interpreter's result.  Note the
;; recorded channels may carry MATCH PATTERNS (==> X or ==> Y, %%% *, %any-error%,
;; %optional-error%); they are honoured by cycle-golden-match? when this playback
;; result is the reference.  Never time out.
(define (make-log-playback name)
  (make-interp name 'log
               (lambda (entry)
                 (make-cycle (entry-output entry) (entry-retval entry)
                             (entry-error entry) #f))))

;; ---- live host runner (in-process; increment 3) --------------------------------
;; The HOST port (whichever interpreter is running this differ) executes each entry's
;; input in a fresh make-environment -- ONE per source, state persisting across
;; cycles, matching the .log runner's reboot-per-file semantics -- via the eval-cycle
;; primitive, which captures output / return value / error using the SAME formatting
;; the .log test runner uses (so results are byte-identical, including error class +
;; line/col).  Honours the entry's fold-case flag exactly as the runner does.

(define host-cycle-timeout 120)   ; seconds; matches the .log runner's per-entry limit

(define (make-host-interp name family)
  (make-stateful-interp name family
    (lambda () (make-toplevel-environment))        ; fresh self-global env per source
    (lambda (env entry)
      (let ((input (if (entry-fold-case entry)
                       (string-append "#!fold-case\n" (entry-input entry))
                       (entry-input entry))))
        (call-with-values
          (lambda () (eval-cycle input env host-cycle-timeout))
          make-cycle)))))

;; ---- live sibling runner (subprocess; increment 3b) ----------------------------
;; Run ANOTHER interpreter that also has eval-cycle / make-toplevel-environment /
;; (read) (i.e. the sibling port) as a subprocess, driven by sibling-driver.scm.  The
;; parent serialises each entry's (input fold-case?) to the child's stdin; the driver
;; runs every entry through the SAME eval-cycle path (one make-toplevel-environment,
;; state preserved) and writes a clean (output retval error timed-out?) per cycle to
;; stdout.  No REPL chrome (eval-cycle gives golden-format errors), no argv length
;; limit (entries go via stdin, not -e), one spawn per source.  LAUNCH-ARGV is how to
;; start the sibling (e.g. (interpreter-argv) for the same port, or a sibling exe
;; path); DRIVER-PATH is the path to sibling-driver.scm.

(define (entries->driver-input items)
  (let ((p (open-output-string)))
    (for-each (lambda (e)
                (write (list (entry-input e) (entry-fold-case e)) p)
                (newline p))
              items)
    (get-output-string p)))

;; Read exactly N (output retval error timed-out?) forms from the driver's stdout into
;; <cycle> results; if the child emitted fewer (e.g. it crashed), pad with an error
;; cycle so the result list always matches the item count.
(define (parse-driver-output text n)
  (let ((p (open-input-string text)))
    (let loop ((k 0) (acc '()))
      (if (>= k n)
          (reverse acc)
          (let ((form (read p)))
            (if (eof-object? form)
                (loop (+ k 1)
                      (cons (make-cycle "" "" "differ: no result from subprocess" #f) acc))
                (loop (+ k 1)
                      (cons (make-cycle (list-ref form 0) (list-ref form 1)
                                        (list-ref form 2) (list-ref form 3)) acc))))))))

(define (make-sibling-interp name family launch-argv driver-path)
  (make-source-interp name family
    (lambda (items)
      (call-with-values
        (lambda () (run-process (append launch-argv (list driver-path))
                                (entries->driver-input items)))
        (lambda (code out err)
          (parse-driver-output out (length items)))))))

;; ---- compare strategies for cycle results --------------------------------------
;; All comparisons live OUTSIDE the core.  The core passes (compare a b); in
;; REFERENCE mode `a` is always the reference (golden) result.

;; Reference vs a .log golden: a = golden (patterns), b = actual subject.  Uses the
;; shared .log match semantics (increment 1) so the differ scores cycles exactly
;; like the existing golden-battery runner.
(define (cycle-golden-match? golden actual)
  (log-match? (cycle-output golden) (cycle-retval golden) (cycle-error golden)
              (cycle-output actual) (cycle-retval actual) (cycle-error actual)
              (cycle-timed-out actual)))

;; Peer STRICT equality (mirror-family, e.g. cpp vs py): all three channels equal.
(define (cycle-strict=? a b)
  (and (string=? (cycle-output a) (cycle-output b))
       (string=? (cycle-retval a) (cycle-retval b))
       (string=? (cycle-error  a) (cycle-error  b))
       (eq? (cycle-timed-out a) (cycle-timed-out b))))

;; Peer COARSE equality (cross-family, e.g. vs chibi): same output and the same
;; errored-or-not flag; return value and error WORDING are not compared.
(define (cycle-coarse=? a b)
  (and (string=? (cycle-output a) (cycle-output b))
       (eq? (cycle-errored? a) (cycle-errored? b))))

;; ---- the CORE: gather + classify -----------------------------------------------

(define-record-type <verdict>
  (make-verdict index item results agree? groups)
  verdict?
  (index   verdict-index)
  (item    verdict-item)
  (results verdict-results)    ; alist (interp-name . result), in interpreter order
  (agree?  verdict-agree?)
  (groups  verdict-groups))    ; peer: list of name-lists (agreement classes)
                               ; reference: (matcher-names . mismatcher-names)

;; Add one named-result to the agreement-class list, preserving discovery order.
;; A class is a list of (name . result); its representative is the first member.
(define (add-to-groups nr compare groups)
  (let loop ((gs groups) (acc '()))
    (cond
      ((null? gs)                                   ; no class matched -> new class
       (reverse (cons (list nr) acc)))
      ((compare (cdr (car (car gs))) (cdr nr))      ; matches this class's rep
       (append (reverse acc) (cons (cons nr (car gs)) (cdr gs))))
      (else (loop (cdr gs) (cons (car gs) acc))))))

(define (partition-peer named compare)
  (let loop ((rs named) (groups '()))
    (if (null? rs) groups
        (loop (cdr rs) (add-to-groups (car rs) compare groups)))))

;; reference = first named-result; every other must compare against it.
(define (classify-reference named compare)
  (let* ((ref-result (cdr (car named)))
         (subjects   (cdr named))
         (matchers    (d-filter (lambda (nr) (compare ref-result (cdr nr))) subjects))
         (mismatchers (d-filter (lambda (nr) (not (compare ref-result (cdr nr)))) subjects)))
    (cons matchers mismatchers)))

(define (classify-item i item named mode compare)
  (cond
    ((eq? mode 'peer)
     (let ((groups (partition-peer named compare)))
       (make-verdict i item named (= 1 (length groups))
                     (map (lambda (g) (map car g)) groups))))
    ((eq? mode 'reference)
     (let* ((mm (classify-reference named compare))
            (matchers (car mm)) (mismatchers (cdr mm)))
       (make-verdict i item named (null? mismatchers)
                     (cons (map car matchers) (map car mismatchers)))))
    (else (error "differ-run: unknown mode (expected 'peer or 'reference)" mode))))

;; Apply RUN to each item in ORDER (not map -- R7RS map's order is unspecified, but a
;; live runner mutating shared state needs strict left-to-right).
(define (run-each-ordered run state items)
  (let loop ((items items) (acc '()))
    (if (null? items)
        (reverse acc)
        (loop (cdr items) (cons (run state (car items)) acc)))))

;; All of one interpreter's results for the whole source, in item order.  A batch
;; (run-source) interpreter produces them in one shot; otherwise init once and run
;; each item with the threaded state.
(define (interp-results ip items)
  (let ((rsrc (interp-run-source ip)))
    (if rsrc
        (rsrc items)
        (run-each-ordered (interp-run ip) ((interp-init ip)) items))))

;; Run every interpreter over the whole source, then classify per item; return a list
;; of verdicts (item order).  In REFERENCE mode the FIRST interpreter is the oracle.
(define (differ-run items interps mode compare)
  (let ((rbi (map (lambda (ip) (cons (interp-name ip) (interp-results ip items)))
                  interps)))           ; rbi = list of (name . results-list)
    (let loop ((items items) (rls (map cdr rbi)) (i 0) (acc '()))
      (if (null? items)
          (reverse acc)
          (let ((named (map (lambda (nr rl) (cons (car nr) (car rl))) rbi rls)))
            (loop (cdr items) (map cdr rls) (+ i 1)
                  (cons (classify-item i (car items) named mode compare) acc)))))))

;; ---- reporting (convenience; renders cycle results) ----------------------------

(define (print-named-cycle nr)
  (display "      ") (display (car nr)) (display ": ")
  (if (cycle? (cdr nr))
      (display (cycle->string (cdr nr)))
      (display "<non-cycle result>"))
  (newline))

(define (print-divergence v mode)
  (display "  cycle ") (display (verdict-index v))
  (let ((item (verdict-item v)))
    (when (and (pair? item) (string? (entry-input item)))
      (display "  input: ") (display (rstrip-nl (entry-input item)))))
  (newline)
  (if (eq? mode 'reference)
      (let ((mismatchers (cdr (verdict-groups v))))
        (display "    disagree with reference: ")
        (display mismatchers) (newline)))
  (for-each print-named-cycle (verdict-results v)))

;; Print every divergent cycle and a summary line.  Returns #t when ALL cycles
;; agree (so callers / ]suites can use it as a pass/fail signal).
(define (differ-report verdicts mode)
  (let* ((divergent (d-filter (lambda (v) (not (verdict-agree? v))) verdicts))
         (n  (length verdicts))
         (nd (length divergent)))
    (for-each (lambda (v) (print-divergence v mode)) divergent)
    (display nd) (display " of ") (display n)
    (display (if (eq? mode 'reference)
                 " cycle(s) disagreed with the reference"
                 " cycle(s) diverged"))
    (newline)
    (= nd 0)))
