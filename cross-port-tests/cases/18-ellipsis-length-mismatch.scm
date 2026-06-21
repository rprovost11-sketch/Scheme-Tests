;;; Regression guard for F1 (FIXED): two same-depth ellipsis pattern variables
;;; matched an unequal number of times, combined in one template.  R7RS 4.3.2
;;; calls this "an error"; both ports now raise a clean syntax error instead of
;;; indexing the shorter match out of bounds (pyScheme used to leak a host
;;; IndexError; cppScheme2 fabricated #<unknown> and SEGFAULTED when the later
;;; var was empty).  This case asserts the two ports stay in lockstep on it.
;;;
;;; NOTE: this intentionally diverges from chibi, which leniently TRUNCATES to
;;; the shorter sequence -- a deliberate R7RS-over-chibi choice, not a bug (a
;;; chibi oracle would flag it as a SHARED-DEVIATION).  The cross-port gate
;;; (]suites cross-port) compares the two ports only, and they stay in lockstep.
(define-syntax zp
  (syntax-rules ()
    ((_ (a ...) (b ...)) (list (list a b) ...))))

(write (zp (1 2 3) (10 20)))
(newline)
