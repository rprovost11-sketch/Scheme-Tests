;;; srfi-166-test.scm -- self-checking conformance test for (srfi 166), core.
;;;
;;; SRFI 166's API is macro-heavy (`with`, `with!`, `fn` are syntax-rules), and the
;;; differ's in-process host cannot resolve macros imported across eval cycles, so
;;; SRFI 166 is tested here as a self-checking program run in a REAL interaction
;;; environment (a child interp loads this file as its main program) rather than via
;;; the .log-through-differ path used for the macro-free SRFIs.  Each check asserts an
;;; EXACT expected string, so passing on both ports proves byte-identical behaviour.
;;;
;;; Run:  <interp> -L <SRFI repo> srfi-166-test.scm   (exits nonzero if any check fails)
;;; Registered as the external ]suites entry  srfi-166 / s166.

(import (scheme base) (scheme write) (scheme char) (srfi 166))

(define pass 0)
(define fail 0)
(define (chk name got want)
  (cond ((equal? got want) (set! pass (+ pass 1)))
        (else (set! fail (+ fail 1))
              (display "FAIL: ") (display name) (newline)
              (display "   want: ") (write want) (newline)
              (display "   got:  ") (write got) (newline))))

;; --- basics ---
(chk 'hello (show #f "hello") "hello")
(chk 'mixed (show #f "a" 42 "b") "a42b")
(chk 'each (show #f (each "x" "y" "z")) "xyz")
(chk 'disp+writ (show #f (displayed "ab") (written "ab")) "ab\"ab\"")
(chk 'written-list (show #f (written (list 1 "two" #\3))) "(1 \"two\" #\\3)")
(chk 'written-simply (show #f (written-simply '(1 2 3))) "(1 2 3)")

;; --- numeric ---
(chk 'prec0 (show #f 1.5 " " (with ((precision 0)) 1.5)) "1.5 2")
(chk 'prec3 (show #f (with ((precision 3)) 1/3)) "0.333")
(chk 'prec50 (show #f (with ((precision 50)) 1/3))
     "0.33333333333333333333333333333333333333333333333333")
(chk 'radix16-with (show #f (with ((radix 16)) (numeric 255))) "ff")
(chk 'radix16-arg (show #f (numeric 255 16)) "ff")
(chk 'radix2 (show #f (numeric 42 2)) "101010")
(chk 'radix36 (show #f (numeric 1295 36)) "zz")
(chk 'sign+ (show #f (with ((sign-rule #t)) (numeric 42))) "+42")
(chk 'neg (show #f (numeric -3.5)) "-3.5")
(chk 'sign-paren (show #f (with ((sign-rule (cons "(" ")"))) (numeric -42))) "(42)")
(chk 'comma (show #f (numeric/comma 123456789)) "123,456,789")
(chk 'comma-list (show #f (numeric/comma 123456789 '(3 2))) "12,34,56,789")
(chk 'comma-sep (show #f (with ((comma-sep #\.) (decimal-sep #\,)) (numeric/comma 1234.5)))
     "1.234,5")

;; --- joins ---
(chk 'joined (show #f (joined displayed '(a b c) ", ")) "a, b, c")
(chk 'joined/prefix (show #f (joined/prefix displayed '(usr local bin) "/")) "/usr/local/bin")
(chk 'joined/suffix (show #f (joined/suffix displayed '(1 2 3) "\n")) "1\n2\n3\n")
(chk 'joined/last
     (show #f (joined/last displayed (lambda (x) (each "and " x)) '(lions tigers bears) ", "))
     "lions, tigers, and bears")
(chk 'joined/dot
     (show #f "(" (joined/dot displayed (lambda (x) (each ". " x)) '(1 2 . 3) " ") ")")
     "(1 2 . 3)")
(chk 'joined/range (show #f (joined/range displayed 0 5 " ")) "0 1 2 3 4")

;; --- padding & spacing ---
(chk 'padded (show #f (padded 5 "abc")) "  abc")
(chk 'padded/right (show #f (padded/right 5 "abc")) "abc  ")
(chk 'padded/both (show #f (padded/both 5 "abc")) " abc ")
(chk 'padded-over (show #f (padded 2 "abc")) "abc")
(chk 'pad-char (show #f (with ((pad-char #\.)) (padded 5 "ab"))) "...ab")
(chk 'space-to (show #f "a" (space-to 5) "b") "a    b")
(chk 'tab-to (show #f "a" (tab-to 5) "b") "a    b")

;; --- trimming & fitting ---
(chk 'trimmed/right (show #f (trimmed/right 5 "abcdef")) "abcde")
(chk 'trimmed (show #f (trimmed 5 "abcdef")) "bcdef")
(chk 'trim-ell-r (show #f (with ((ellipsis "...")) (trimmed/right 5 "abcdef"))) "ab...")
(chk 'trim-ell-both (show #f (with ((ellipsis "X")) (trimmed/both 5 "abcdef"))) "XbcdX")
(chk 'fitted-pad (show #f (fitted 5 "abc")) "abc  ")
(chk 'fitted-trim (show #f (fitted 5 "abcdef")) "abcde")
(chk 'fitted/right (show #f (fitted/right 5 "abc")) "  abc")

;; --- case ---
(chk 'upcased (show #f (upcased "abc")) "ABC")
(chk 'downcased (show #f (downcased "ABC")) "abc")

;; --- escaping ---
(chk 'escaped (show #f (escaped "hi, \"bob!\"")) "hi, \\\"bob!\\\"")
(chk 'maybe-no (show #f (maybe-escaped "foo" char-whitespace? #\")) "foo")
(chk 'maybe-yes (show #f (maybe-escaped "foo bar" char-whitespace? #\")) "\"foo bar\"")

;; --- state machinery ---
(chk 'fn-col (show #f "abc" (fn ((c col)) (each "@" (number->string c)))) "abc@3")
(chk 'with! (show #f (each (with! ((radix 2)) "") (numeric 5))) "101")
(chk 'with-restore (show #f (with ((radix 2)) (numeric 5)) (numeric 5)) "1015")
(chk 'fl (show #f "a" fl "b" fl) "a\nb\n")
(chk 'fl-noop (show #f fl "a") "a")
(chk 'nothing (show #f "a" nothing "b") "ab")
(chk 'forked (show #f (forked (each "x") "y")) "xy")

(newline)
(display "srfi-166: ") (display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(exit (if (= fail 0) 0 1))
