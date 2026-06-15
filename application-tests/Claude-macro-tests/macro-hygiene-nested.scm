;;; ===========================================================================
;;; Acceptance battery: macro hygiene -- nested macros & free-identifier identity
;;; ===========================================================================
;;; A self-checking spec for the deep syntax-rules / hygiene cases that the
;;; chibi r7rs-tests survey (and adjacent probing) exposed and that the current
;;; name-based hygiene model does NOT get right.  Every expected value was
;;; verified against chibi-scheme (the R7RS-conformant reference) via its REPL.
;;;
;;;   A1  "macro that generates a macro": an identifier threaded through an
;;;       outer macro into a NESTED syntax-rules definition must keep its own
;;;       identity -- not captured by, nor capturing, the inner macro's
;;;       like-named pattern variables / bindings.
;;;   A3  bound-identifier=? vs free-identifier=?: whether two identifiers are
;;;       the *same* identifier (name + marks) or merely share a name.  Probed
;;;       indirectly through which syntax-rules clause fires.
;;;   A5  free-variable identity: a template's free reference to a variable that
;;;       was already bound when the macro was defined (the common top-level
;;;       `define x` then `define-syntax`) must resolve to that *binding*, not a
;;;       snapshot copy -- so set! writes through and later mutations are seen.
;;;
;;; Cases tagged [DISCRIMINATES] currently FAIL on pyScheme / cppScheme2 -- they
;;; are the real test of a fix.  Cases tagged [guard] already pass and must KEEP
;;; passing (regression guard against an over-eager fix).
;;;
;;; Run (file mode):  python -m pyscheme <file>   |   cppscheme2.exe <file>
;;; chibi runs these only from its REPL (its file compiler mishandles a
;;; macro-generated define-syntax with empty literals); feed bodies on stdin.
;;; ===========================================================================

(define pass 0)
(define fail 0)

;; A plain procedure (NOT a macro): its arguments are evaluated by the caller,
;; so each test expression runs in its own right and we avoid having the harness
;; itself depend on the very hygiene behaviour under test (see A5).
(define (check label a e)
  (if (equal? a e)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL [") (display label) (display "] got ")
        (write a) (display " expected ") (write e) (newline))))

;;; --------------------------------------------------------------------------
;;; A1 -- macro that generates a macro
;;; --------------------------------------------------------------------------

;; [DISCRIMINATES] The inner template's 'y is foo's argument (the use-site x),
;; NOT the inner macro's pattern variable x.  Expected: the symbol x.
(check "A1a/threaded-quote"
       (let ()
         (define-syntax foo
           (syntax-rules ()
             ((foo bar y)
              (define-syntax bar
                (syntax-rules () ((bar x) 'y))))))
         (foo bar x)
         (bar 1))
       'x)

;; [DISCRIMINATES] Both identities visible at once: inner pattern var x = 1,
;; threaded y = symbol x.
(check "A1b/both-identities"
       (let ()
         (define-syntax foo
           (syntax-rules ()
             ((foo bar y)
              (define-syntax bar
                (syntax-rules () ((bar x) (list x 'y)))))))
         (foo bar x)
         (bar 1))
       '(1 x))

;; [guard] Inner pattern var name differs from the threaded id: no name clash.
(check "A1c/distinct-names"
       (let ()
         (define-syntax foo
           (syntax-rules ()
             ((foo mac arg)
              (define-syntax mac
                (syntax-rules () ((mac p) (cons p 'arg)))))))
         (foo bar hello)
         (bar 1))
       '(1 . hello))

;; [guard] Threaded id placed in the inner macro's LITERALS list: the literal
;; matches a use-site identifier of the same origin, and only that one.
(check "A1d/threaded-into-literals"
       (let ()
         (define-syntax gen
           (syntax-rules ()
             ((gen m tok)
              (define-syntax m
                (syntax-rules (tok)
                  ((m tok) 'saw-token)
                  ((m other) 'other-token))))))
         (gen pick zzz)
         (list (pick zzz) (pick qqq)))
       '(saw-token other-token))

;; [guard] Two macros built by the same generator stay independent.
(check "A1e/two-generated"
       (let ()
         (define-syntax foo
           (syntax-rules ()
             ((foo bar y)
              (define-syntax bar
                (syntax-rules () ((bar x) 'y))))))
         (foo m1 aaa)
         (foo m2 bbb)
         (list (m1 1) (m2 2)))
       '(aaa bbb))

;; [DISCRIMINATES] The generated macro introduces a binding using the threaded
;; id; a use-site reference of the same name must NOT be captured by it.  The
;; (let ((y 'inner)) ...) binds the threaded y; the use-site x passed as e must
;; stay the outer x.  Expected: ((inner outer) outer).
(check "A1f/generated-binding-no-capture"
       (let ((x 'outer))
         (define-syntax foo
           (syntax-rules ()
             ((foo bar y)
              (define-syntax bar
                (syntax-rules ()
                  ((bar e) (let ((y 'inner)) (list y e))))))))
         (foo bar x)
         (list (bar x) x))
       '((inner outer) outer))

;;; --------------------------------------------------------------------------
;;; A3 -- bound-identifier=? vs free-identifier=?
;;; --------------------------------------------------------------------------

;; [DISCRIMINATES] r7rs-tests canonical case.  m's pattern var x is substituted
;; with the use-site k into n's first pattern; because that k carries different
;; marks than n's literal k, it stays a pattern variable, so (n z) matches it.
(check "A3a/canonical"
       (let-syntax
           ((m (syntax-rules ()
                 ((m x)
                  (let-syntax
                      ((n (syntax-rules (k)
                            ((n x) 'bound-identifier=?)
                            ((n y) 'free-identifier=?))))
                    (n z))))))
         (m k))
       'bound-identifier=?)

;; [guard] m applied to a non-literal id: first clause's x is a plain pattern
;; var, so it always matches.
(check "A3b/non-literal-arg"
       (let-syntax
           ((m (syntax-rules ()
                 ((m x)
                  (let-syntax
                      ((n (syntax-rules (k)
                            ((n x) 'matched-x)
                            ((n y) 'matched-y))))
                    (n z))))))
         (m w))
       'matched-x)

;; [guard] Body applies n to the literal k directly.
(check "A3c/body-is-literal"
       (let-syntax
           ((m (syntax-rules ()
                 ((m x)
                  (let-syntax
                      ((n (syntax-rules (k)
                            ((n x) 'bound=)
                            ((n y) 'free=))))
                    (n k))))))
         (m k))
       'bound=)

;; [DISCRIMINATES] n has its OWN literal k (first clause), then x->k as a second
;; clause, then a catch-all.  The substituted k is a pattern var (different
;; marks than the literal k), so (n z) matches the x-clause.  Expected: var-x.
(check "A3d/own-literal-plus-substituted"
       (let-syntax
           ((m (syntax-rules ()
                 ((m x)
                  (let-syntax
                      ((n (syntax-rules (k)
                            ((n k) 'lit-k)
                            ((n x) 'var-x)
                            ((n other) 'other))))
                    (n z))))))
         (m k))
       'var-x)

;; [guard] User-supplied literal name matches a same-origin use-site arg.
(check "A3e/user-literal-match"
       (let-syntax
           ((m (syntax-rules ()
                 ((m a b)
                  (let-syntax
                      ((n (syntax-rules (a)
                            ((n a) 'is-a)
                            ((n z) 'not-a))))
                    (n b))))))
         (m foo foo))
       'is-a)

;; [guard] ...and does NOT match a different use-site arg.
(check "A3f/user-literal-no-match"
       (let-syntax
           ((m (syntax-rules ()
                 ((m a b)
                  (let-syntax
                      ((n (syntax-rules (a)
                            ((n a) 'is-a)
                            ((n z) 'not-a))))
                    (n b))))))
         (m foo bar))
       'not-a)

;;; --------------------------------------------------------------------------
;;; A5 -- free-variable identity (must resolve to the binding, not a copy)
;;; These use genuine top-level definitions: the variable is bound BEFORE the
;;; macro is defined, which is what trips the free_id_map snapshot.  (The same
;;; macros written inside a local body currently work, so they would not
;;; discriminate -- the bug is specific to def-before-macro bindings.)
;;; --------------------------------------------------------------------------

;; [DISCRIMINATES] set! inside a template must write through to the variable,
;; not to a private copy.
(define a5-counter 0)
(define-syntax a5-bump
  (syntax-rules () ((a5-bump) (set! a5-counter (+ a5-counter 1)))))
(a5-bump) (a5-bump) (a5-bump)
(check "A5a/set-through-counter" a5-counter 3)

;; [DISCRIMINATES] a template's read of a variable mutated AFTER the macro was
;; defined must see the new value, not the def-time snapshot.
(define a5-g 10)
(define-syntax a5-getg (syntax-rules () ((a5-getg) a5-g)))
(set! a5-g 20)
(check "A5b/stale-read-after-mutation" (a5-getg) 20)

;; [DISCRIMINATES] macro writes, ordinary code reads.
(define a5-h 0)
(define-syntax a5-seth (syntax-rules () ((a5-seth v) (set! a5-h v))))
(a5-seth 99)
(check "A5c/macro-write-plain-read" a5-h 99)

;;; --------------------------------------------------------------------------
;;; Summary
;;; --------------------------------------------------------------------------
(display "=== macro hygiene battery: ")
(display pass) (display " passed, ")
(display fail) (display " failed ===")
(newline)
