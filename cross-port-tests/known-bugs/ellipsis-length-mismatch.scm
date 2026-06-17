;;; QUARANTINED REPRO -- do NOT move to cases/ until BOTH ports are fixed
;;; (it crashes cppScheme2, which would break the gating harness).
;;;
;;; Two same-depth ellipsis pattern variables of UNEQUAL length, used together
;;; in one template.  Per R7RS 4.3.2 this is "an error"; chibi tolerates it by
;;; truncating to the shorter.  Both ports mishandle it when a LATER var is the
;;; shorter one (the first var drives the iteration count):
;;;
;;;   (zp (1 2 3) (10 20))   chibi=> ((1 10)(2 20))   [truncates]
;;;                          py   => "list index out of range"  [host IndexError]
;;;                          cpp  => ((1 10)(2 20)(3 #<unknown>))  [fabricated value]
;;;
;;;   (zp (1 2) ())          chibi=> ()
;;;                          py   => "list index out of range"  [host IndexError]
;;;                          cpp  => SEGFAULT (rc 139)           [out-of-bounds read]
;;;
;;; FIX TARGET: the template-instantiation loop in each port's syntax-rules
;;; expander must detect mismatched ellipsis match-counts and raise a clean
;;; Scheme-level syntax error (pyScheme must not leak a Python IndexError;
;;; cppScheme2 must not read past the shorter sequence).  When fixed, promote a
;;; well-formed version of this to cases/ as a regression guard.
(define-syntax zp
  (syntax-rules ()
    ((_ (a ...) (b ...)) (list (list a b) ...))))

(write (zp (1 2 3) (10 20)))
(newline)
