;;; differ-portability-body.scm -- the shared body of the differ-core portability
;;; test.  It has NO import / no record-type prologue, so each interpreter family can
;;; supply its own before `(include)`-ing this file:
;;;   * differ-portability.scm       -- R7RS: (import (scheme base) (scheme write))
;;;   * differ-portability-chez.scm  -- Chez: a vector-backed define-record-type shim
;;; This keeps the actual test in ONE place (no drift) while the only per-impl
;;; difference -- how `define-record-type` and the basic procedures become available --
;;; lives in the tiny wrapper.
;;;
;;; It splices the REAL differ.scm (no copy) and exercises ONLY the pure classification
;;; core with MOCK interpreters: no extension primitive (parse-log-file / log-match? /
;;; eval-cycle / make-toplevel-environment / run-process / interpreter-argv /
;;; directory-files) is ever CALLED.  The stubs below merely give those a binding so
;;; the include succeeds where they are absent (on cppScheme2/pyScheme the real ones
;;; exist and the stubs harmlessly shadow them -- never run).  Prints ONE canonical
;;; line that every interpreter must reproduce byte-for-byte.

;; --- stubs so including differ.scm succeeds where the extension primitives are absent
(define (parse-log-file . _)            (error "differ-portability: stub not callable"))
(define (log-match? . _)                (error "differ-portability: stub not callable"))
(define (log-match-detail . _)          (error "differ-portability: stub not callable"))
(define (eval-cycle . _)                (error "differ-portability: stub not callable"))
(define (make-toplevel-environment . _) (error "differ-portability: stub not callable"))
(define (run-process . _)               (error "differ-portability: stub not callable"))
(define (interpreter-argv . _)          (error "differ-portability: stub not callable"))
(define (directory-files . _)           (error "differ-portability: stub not callable"))

;; `include` (not `load`) splices the real engine in: plain R7RS, no (scheme load).
(include "differ.scm")

;; --- mock run-fns: each maps an item to a <cycle> with no live execution ----------
(define (agree-fn it)  (make-cycle "out" "" "" #f))           ; same result everywhere
(define (vary-fn  it)  (make-cycle (if (equal? it "y") "DIFF" "out") "" "" #f))
(define (other-fn it)  (make-cycle "OTHER" "" "" #f))         ; always differs from agree
(define (errA-fn  it)  (make-cycle "out" "" "Error: foo" #f)) ; errored, wording A
(define (errB-fn  it)  (make-cycle "out" "" "different wording here" #f)) ; errored, wording B

(define (n-diverged vs) (d-count (lambda (v) (not (verdict-agree? v))) vs))
(define (mk name fn) (make-interp name 'mock fn))

;; PEER, all agree -> 0 diverge
(define peer-agree
  (= 0 (n-diverged (differ-run (list "x" "y")
                               (list (mk "a" agree-fn) (mk "b" agree-fn) (mk "c" agree-fn))
                               'peer cycle-strict=?))))

;; PEER, one diverges on the 2nd cycle only -> exactly 1 diverge
(define peer-diverge
  (= 1 (n-diverged (differ-run (list "x" "y")
                               (list (mk "a" agree-fn) (mk "b" agree-fn) (mk "c" vary-fn))
                               'peer cycle-strict=?))))

;; REFERENCE, subject matches the oracle -> 0 diverge (strict compare, no log-match?)
(define ref-ok
  (= 0 (n-diverged (differ-run (list "x")
                               (list (mk "gold" agree-fn) (mk "subj" agree-fn))
                               'reference cycle-strict=?))))

;; REFERENCE, subject disagrees with the oracle -> exactly 1 diverge
(define ref-bad
  (= 1 (n-diverged (differ-run (list "x")
                               (list (mk "gold" agree-fn) (mk "subj" other-fn))
                               'reference cycle-strict=?))))

;; STRICTNESS lives in the compare: same output, different error WORDING (both errored)
;;   -> strict diverges, coarse agrees.
(define strict-diverges
  (not (verdict-agree?
        (car (differ-run (list 'one) (list (mk "a" errA-fn) (mk "b" errB-fn))
                         'peer cycle-strict=?)))))
(define coarse-agrees
  (verdict-agree?
   (car (differ-run (list 'one) (list (mk "a" errA-fn) (mk "b" errB-fn))
                    'peer cycle-coarse=?))))

;; --- the canonical line every interpreter must reproduce byte-for-byte ------------
(display "(peer-agree ")    (write peer-agree)
(display " peer-diverge ")  (write peer-diverge)
(display " ref-ok ")        (write ref-ok)
(display " ref-bad ")       (write ref-bad)
(display " coarse ")        (write coarse-agrees)
(display " strict ")        (write strict-diverges)
(display ")")               (newline)
