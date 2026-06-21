;;; correctness-slow.scm -- full timed cpp-vs-py ecraven differential (shell-free).
;;;
;;; The thorough counterpart of correctness-inprocess.scm: it runs EVERY benchmark
;;; through BOTH ports as subprocesses under a per-benchmark timeout (heavy
;;; benchmarks a tree-walker can't finish in correctness mode), classifies each
;;; OK / INCORRECT / CRASH / TIMEOUT, and flags a cpp-vs-py correctness DIVERGENCE
;;; (one port OK while the other is INCORRECT/CRASH).  A timeout on a side is
;;; INCONCLUSIVE (a speed difference, not a bug).  Replaces correctness-sweep.sh:
;;; the timeout comes from (run-process ... timeout), so no shell / GNU timeout.
;;;
;;; HOSTED ON pyScheme (registry slow variant: ports py) -- same PYTHONPATH reason
;;; as the cross-port differential; the cpp side is the sibling exe by a known
;;; relative path.  Run from the benchmark dir so relative aux inputs resolve.
;;;
;;; Env knobs: ECRAVEN_TIMEOUT (seconds/benchmark, default 60);
;;;            ECRAVEN_ONLY ("a b c" -> just those benchmarks; default all).

(import (scheme base) (scheme file) (scheme write) (scheme process-context))

(define (read-file-string path)
  (call-with-port (open-input-file path)
    (lambda (p)
      (let loop ((acc '()))
        (let ((c (read-char p)))
          (if (eof-object? c) (list->string (reverse acc)) (loop (cons c acc))))))))

(define (contains? hay needle)
  (let ((hn (string-length hay)) (nn (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i nn) hn) #f)
            ((string=? (substring hay i (+ i nn)) needle) #t)
            (else (loop (+ i 1)))))))

(define (string-suffix? suf s)
  (let ((ls (string-length s)) (lu (string-length suf)))
    (and (>= ls lu) (string=? (substring s (- ls lu) ls) suf))))

(define (xfilter pred lst)
  (cond ((null? lst) '()) ((pred (car lst)) (cons (car lst) (xfilter pred (cdr lst))))
        (else (xfilter pred (cdr lst)))))

(define (split-ws s)                 ; split on spaces into nonempty tokens
  (let ((n (string-length s)))
    (let loop ((i 0) (start #f) (acc '()))
      (cond ((>= i n) (reverse (if start (cons (substring s start n) acc) acc)))
            ((char=? (string-ref s i) #\space)
             (loop (+ i 1) #f (if start (cons (substring s start i) acc) acc)))
            (else (loop (+ i 1) (if start start i) acc))))))

(define (env-num name default)
  (let* ((e (get-environment-variable name)) (n (and e (string->number e))))
    (if (and n (real? n) (> n 0)) n default)))

(define timeout (env-num "ECRAVEN_TIMEOUT" 60))
(define only (let ((e (get-environment-variable "ECRAVEN_ONLY")))
               (if (and e (> (string-length e) 0)) (split-ws e) #f)))

(define py-argv (interpreter-argv))                              ; self (py)
(define cpp-argv (list "../../../4CPPScheme2/build/Release/cppscheme2.exe"))  ; sibling

;; Correctness shim: run the thunk ONCE (ignore the timing iteration count) and
;; report pass/fail.  Appended after common.scm (which defines the timing version)
;; so this redefinition wins when (run-benchmark) calls run-r7rs-benchmark.
(define shim
  (string-append
   "(define (this-scheme-implementation-name) \"x\")\n"
   "(define (run-r7rs-benchmark name count thunk ok?)\n"
   "  (if (ok? (thunk)) (begin (display \"RESULT:OK\") (newline))\n"
   "      (begin (display \"RESULT:INCORRECT\") (newline))))\n"))

(define scratch "correctness-slow-scratch.scm")

;; run-process returns #f exit-code on timeout; classify the (code, output).
(define (classify code out)
  (cond ((not code) 'TIMEOUT)
        ((contains? out "RESULT:OK") 'OK)
        ((contains? out "RESULT:INCORRECT") 'INCORRECT)
        ((not (= code 0)) 'CRASH)
        (else 'NORESULT)))

(define (run-port argv stdin-data)
  (call-with-values
    (lambda () (run-process (append argv (list scratch)) stdin-data timeout))
    (lambda (code out err) (classify code (string-append out err)))))

(define (sym->string s) (symbol->string s))

(define benches
  (let ((all (map (lambda (n) (substring n 0 (- (string-length n) 6)))   ; strip ".input"
                  (xfilter (lambda (n) (string-suffix? ".input" n)) (directory-files "inputs")))))
    (if only (xfilter (lambda (b) (and (member b only) #t)) all) all)))

(display "ecraven correctness sweep (full, timeout=") (display timeout)
(display "s/benchmark)") (newline)
(display "  cpp: ") (display (car cpp-argv)) (newline)
(display "  py : ") (for-each (lambda (a) (display a) (display " ")) py-argv) (newline) (newline)

(define agree 0)
(define diverged '())
(define inconclusive 0)

(for-each
 (lambda (bench)
   (let ((bench-file (string-append "src/" bench ".scm")))
     (when (file-exists? bench-file)
       (let ((src (string-append (read-file-string bench-file) "\n"
                                 (read-file-string "src/common.scm") "\n"
                                 shim "\n(run-benchmark)\n"))
             (stdin-data (read-file-string (string-append "inputs/" bench ".input"))))
         (when (file-exists? scratch) (delete-file scratch))
         (call-with-output-file scratch (lambda (p) (write-string src p)))
         (let* ((cc (run-port cpp-argv stdin-data))
                (pc (run-port py-argv stdin-data))
                (note (cond ((or (eq? cc 'TIMEOUT) (eq? pc 'TIMEOUT)
                                 (eq? cc 'NORESULT) (eq? pc 'NORESULT))
                             (set! inconclusive (+ inconclusive 1)) "inconclusive")
                            ((eq? cc pc)
                             (if (eq? cc 'OK) (begin (set! agree (+ agree 1)) "")
                                 (string-append "both " (sym->string cc))))
                            (else
                             (set! diverged (cons bench diverged)) "*** DIVERGENCE ***"))))
           (display "  ") (display bench) (display "  cpp=") (display (sym->string cc))
           (display " py=") (display (sym->string pc))
           (if (string=? note "") (newline)
               (begin (display "  ") (display note) (newline))))))))
 benches)
(when (file-exists? scratch) (delete-file scratch))

(newline)
(display "summary: ") (display agree) (display " agree-OK, ")
(display (length diverged)) (display " DIVERGENCE, ")
(display inconclusive) (display " inconclusive(timeout/noresult)") (newline)
(for-each (lambda (b) (display "    DIVERGENCE  ") (display b) (newline)) (reverse diverged))
(exit (if (null? diverged) 0 1))
