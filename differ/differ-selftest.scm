;;; differ-selftest.scm -- self-test for the differ CORE (increment 2).
;;;
;;; Run from this directory on EITHER port, e.g.
;;;   python -m pyscheme differ-selftest.scm                 (from 3PyScheme cwd? no:)
;;;   <interp> differ-selftest.scm        (run with cwd = scheme-tests/differ)
;;; Exits 0 if every check passes, 1 otherwise.  Uses mock interpreters (canned
;;; run-fns) to exercise the core's classification independently of live
;;; execution (which arrives in increment 3), plus a real .log fixture driven
;;; through parse-log-file / log-match? to prove the .log-as-reference path.

(import (scheme base) (scheme write) (scheme file) (scheme process-context))
(load "differ.scm")

;; ---- tiny assert harness -------------------------------------------------------

(define *pass* 0)
(define *fail* 0)
(define (check name actual expected)
  (if (equal? actual expected)
      (set! *pass* (+ *pass* 1))
      (begin (set! *fail* (+ *fail* 1))
             (display "  FAIL: ") (display name)
             (display "  expected=") (write expected)
             (display " actual=") (write actual) (newline))))
(define (check-true  name x) (check name (and x #t) #t))
(define (check-false name x) (check name (and x #t) #f))
(define (n-diverged verdicts)
  (d-count (lambda (v) (not (verdict-agree? v))) verdicts))

;; ================================================================================
;; A. PEER mode, all interpreters agree.
;; ================================================================================
(let* ((items (list "x" "y"))
       (same  (lambda (it) (make-cycle it "" "" #f)))
       (verdicts (differ-run items
                             (list (make-interp "a" 'mock same)
                                   (make-interp "b" 'mock same)
                                   (make-interp "c" 'mock same))
                             'peer cycle-strict=?)))
  (check "A: 2 cycles" (length verdicts) 2)
  (check "A: none diverge" (n-diverged verdicts) 0)
  (check "A: single agreement class" (length (verdict-groups (car verdicts))) 1))

;; ================================================================================
;; B. PEER mode, one interpreter diverges on the 2nd cycle only.
;; ================================================================================
(let* ((items (list "x" "y"))
       (good (lambda (it) (make-cycle it "" "" #f)))
       (bad  (lambda (it) (make-cycle (if (string=? it "y") "DIFFERENT" it) "" "" #f)))
       (verdicts (differ-run items
                             (list (make-interp "a" 'mock good)
                                   (make-interp "b" 'mock good)
                                   (make-interp "c" 'mock bad))
                             'peer cycle-strict=?)))
  (check "B: only 2nd diverges" (n-diverged verdicts) 1)
  (check-true  "B: cycle 0 agrees"     (verdict-agree? (car verdicts)))
  (check-false "B: cycle 1 disagrees"  (verdict-agree? (cadr verdicts)))
  (check "B: cycle 1 has 2 classes" (length (verdict-groups (cadr verdicts))) 2))

;; ================================================================================
;; C. REFERENCE mode against a real .log golden (parse-log-file + log-match?).
;;    The golden carries match patterns: '==> 1 or ==> 2' and '%%% *'.
;; ================================================================================
(define fixture "differ-selftest-fixture.log")
(when (file-exists? fixture) (delete-file fixture))
(call-with-output-file fixture
  (lambda (p)
    (write-string ">>> (+ 1 2)\n==> 3\n" p)
    (write-string ">>> (pick)\n==> 1 or ==> 2\n" p)
    (write-string ">>> (car (quote ()))\n%%% *\n" p)))

(define golden (make-log-playback "golden"))

;; A subject mock that "executes" by switching on the recorded input.
(define (subject-mock name foo-retval)
  (make-interp name 'mock
    (lambda (e)
      (let ((in (rstrip-nl (entry-input e))))
        (cond ((string=? in "(+ 1 2)")       (make-cycle "" "3" "" #f))
              ((string=? in "(pick)")         (make-cycle "" foo-retval "" #f))
              (else                           (make-cycle "" "" "car: not a pair" #f)))))) )

(let* ((items (log-source fixture))
       (verdicts (differ-run items
                             (list golden (subject-mock "subject" "2")) ; "2" matches the alt
                             'reference cycle-golden-match?)))
  (check "C-good: 3 cycles" (length verdicts) 3)
  (check "C-good: none disagree" (n-diverged verdicts) 0)
  (check-true "C-good: report says all agree" (differ-report verdicts 'reference)))

(let* ((items (log-source fixture))
       (verdicts (differ-run items
                             (list golden (subject-mock "subject" "9")) ; "9" matches neither alt
                             'reference cycle-golden-match?)))
  (check "C-bad: exactly 1 disagrees" (n-diverged verdicts) 1)
  (check-false "C-bad: the (pick) cycle disagrees" (verdict-agree? (cadr verdicts)))
  (check "C-bad: subject is the mismatcher"
         (cdr (verdict-groups (cadr verdicts))) '("subject")))

(when (file-exists? fixture) (delete-file fixture))

;; ================================================================================
;; D. Strictness lives in the compare predicate, not the core.  Two results with
;;    the same output but different error WORDING (both errored): strict diverges,
;;    coarse agrees.
;; ================================================================================
(let* ((a (make-cycle "out" "" "Error: foo" #f))
       (b (make-cycle "out" "" "totally different wording" #f))
       (interps (list (make-interp "a" 'mock (lambda (_) a))
                      (make-interp "b" 'mock (lambda (_) b)))))
  (check-false "D: strict diverges"
               (verdict-agree? (car (differ-run (list 'one) interps 'peer cycle-strict=?))))
  (check-true  "D: coarse agrees"
               (verdict-agree? (car (differ-run (list 'one) interps 'peer cycle-coarse=?)))))

;; ---- summary -------------------------------------------------------------------
(display "differ selftest: ") (display *pass*) (display " passed, ")
(display *fail*) (display " failed") (newline)
(exit (if (= *fail* 0) 0 1))
