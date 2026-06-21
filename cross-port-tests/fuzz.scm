;;; fuzz.scm -- grammar-based differential macro fuzzer (shell-free).
;;;
;;; Generates random but VALID-BY-CONSTRUCTION syntax-rules programs and runs each
;;; through BOTH ports via the cross-port-common engine, reporting where they
;;; disagree.  Validity-by-construction matters: a fully random generator produces
;;; mostly parse errors (divergence noise); here every program is a macro plus a
;;; USE built to match one of its clauses, so it runs to a value and a divergence
;;; is a real macro-expansion bug.  The shapes target the ellipsis / hygiene
;;; corners where the two hand-ported expanders are most likely to drift apart.
;;; Replaces the Python fuzz.py (which `import diff`); here we (load) the same
;;; shared engine.
;;;
;;; HOSTED ON pyScheme (registry: ports py) -- same PYTHONPATH reason as diff.scm.
;;; The generator (the seeded RNG) runs only in the host (py); each program is
;;; written to one scratch file and run through both ports, so a single host gives
;;; deterministic, repeatable programs.  N and SEED are fixed here (interpreters
;;; reject extra argv, so they can't be passed on the command line).
;;;
;;; Run (from cross-port-tests/, hosted on pyScheme):  <pyscheme> fuzz.scm

(import (scheme base) (scheme write) (scheme file) (scheme process-context))
(load "cross-port-common.scm")     ; run-case, behaves-like?, divergence-kind, show, py/cpp-argv

;; ---- seeded PRNG (LCG; R7RS has no seeded RNG -- exact sequence is irrelevant,
;;      only determinism per seed) -------------------------------------------------
(define (make-rng seed)
  (let ((state (modulo (+ seed 2147483647) 2147483648)))
    (lambda (n)                               ; -> integer in [0, n)
      (set! state (modulo (+ (* state 1103515245) 12345) 2147483648))
      (modulo (quotient state 65536) n))))

(define (rand-int rng lo hi) (+ lo (rng (+ 1 (- hi lo)))))   ; inclusive
(define (rand-choice rng lst) (list-ref lst (rng (length lst))))
(define (rand-bool rng) (= 0 (rng 2)))

(define (repeat-n n thunk)
  (let loop ((i 0) (acc '())) (if (>= i n) (reverse acc) (loop (+ i 1) (cons (thunk) acc)))))
(define (sjoin sep lst)
  (cond ((null? lst) "")
        ((null? (cdr lst)) (car lst))
        (else (string-append (car lst) sep (sjoin sep (cdr lst))))))
(define (parend lst) (string-append "(" (sjoin " " lst) ")"))

(define (datum rng) (number->string (rand-int rng 0 99)))
(define (group rng lo hi) (repeat-n (rand-int rng lo hi) (lambda () (datum rng))))

;; clauses = list of (pattern . template) -> a (define-syntax m ...) string
(define (defmac clauses)
  (string-append
   "(define-syntax m\n  (syntax-rules ()\n    "
   (sjoin "\n    " (map (lambda (c) (string-append "(" (car c) " " (cdr c) ")")) clauses))
   "))\n"))

;; ---- shapes: each (rng) -> (src . note) ----------------------------------------

(define (shape-zip rng)              ; two same-depth ellipsis vars in one template
  (let* ((n (rand-int rng 1 4)) (a (group rng n n)) (b (group rng n n)))
    (cons (string-append (defmac (list (cons "(_ (a ...) (b ...))" "(list (list a b) ...)")))
                         "(write (m " (parend a) " " (parend b) "))(newline)\n")
          (string-append "zip n=" (number->string n)))))

(define (shape-flatten rng)          ; double-splice: (list a ... ...)
  (let* ((ng (rand-int rng 1 4)) (groups (repeat-n ng (lambda () (group rng 0 3)))))
    (cons (string-append (defmac (list (cons "(_ (a ...) ...)" "(list a ... ...)")))
                         "(write (m " (sjoin " " (map parend groups)) "))(newline)\n")
          (string-append "flatten " (number->string ng) " groups"))))

(define (shape-transpose rng)        ; nested ellipsis preserved: ((a ...) ...)
  (let* ((ng (rand-int rng 1 3)) (groups (repeat-n ng (lambda () (group rng 1 3)))))
    (cons (string-append (defmac (list (cons "(_ (a ...) ...)" "(list (list a ...) ...)")))
                         "(write (m " (sjoin " " (map parend groups)) "))(newline)\n")
          (string-append "transpose " (number->string ng) " groups"))))

(define (shape-fold rng)             ; inner fold: ((a ...) ...) -> ((+ a ...) ...)
  (let* ((ng (rand-int rng 1 3)) (groups (repeat-n ng (lambda () (group rng 1 4)))))
    (cons (string-append (defmac (list (cons "(_ (a ...) ...)" "(list (+ a ...) ...)")))
                         "(write (m " (sjoin " " (map parend groups)) "))(newline)\n")
          (string-append "fold " (number->string ng) " groups"))))

(define (shape-broadcast rng)        ; depth-0 var across a depth-1 ellipsis
  (let* ((x (datum rng)) (ys (group rng 0 5)))
    (cons (string-append (defmac (list (cons "(_ x (a ...))" "(list (cons x a) ...)")))
                         "(write (m " x " " (parend ys) "))(newline)\n")
          (string-append "broadcast |a|=" (number->string (length ys))))))

(define (shape-fixed-tail rng)       ; ellipsis with fixed prefix + suffix
  (let* ((pre (datum rng)) (mid (group rng 0 4)) (suf (datum rng)))
    (cons (string-append (defmac (list (cons "(_ p a ... s)" "(list p (list a ...) s)")))
                         "(write (m " pre " " (sjoin " " mid) " " suf "))(newline)\n")
          (string-append "fixed-tail |mid|=" (number->string (length mid))))))

(define (shape-vector rng)           ; vector pattern + vector template
  (let ((xs (group rng 0 5)))
    (cons (string-append (defmac (list (cons "(_ #(a ...))" "(vector a ... a ...)")))
                         "(write (m #(" (sjoin " " xs) ")))(newline)\n")
          (string-append "vector |a|=" (number->string (length xs))))))

(define (shape-dotted rng)           ; dotted tail pattern
  (let* ((head (datum rng)) (tail (group rng 0 3))
         (use (if (null? tail) (string-append "(" head ")")
                  (string-append "(" head " " (sjoin " " tail) ")"))))
    (cons (string-append (defmac (list (cons "(_ (a . b))" "(cons 'a 'b)")))
                         "(write (m " use "))(newline)\n")
          (string-append "dotted |tail|=" (number->string (length tail))))))

(define (shape-recursive-or rng)     ; recursive macro w/ hygienic temporary `t`
  (let* ((n (rand-int rng 0 5))
         (args (repeat-n n (lambda () (if (rand-bool rng) "#f" (datum rng)))))
         (collide (rand-bool rng))
         (cd (if collide (datum rng) "")))
    (cons (string-append
            "(define-syntax m\n  (syntax-rules ()\n"
            "    ((_) #f)\n    ((_ e) e)\n"
            "    ((_ e1 e2 ...) (let ((t e1)) (if t t (m e2 ...))))))\n"
            (if collide (string-append "(define t " cd ")\n") "")
            "(write (m " (sjoin " " args) "))(newline)\n")
          (string-append "recursive-or n=" (number->string n)))))

(define (shape-let-star rng)         ; recursive let* macro
  (let ((k (rand-int rng 0 4)) (vars (list "a" "b" "c" "d" "e" "f" "g" "h")))
    (let loop ((i 0) (prev #f) (binds '()) (names '()))
      (if (>= i k)
          (cons (string-append
                  "(define-syntax ml\n  (syntax-rules ()\n"
                  "    ((_ () body ...) (begin body ...))\n"
                  "    ((_ ((x v) rest ...) body ...) (let ((x v)) (ml (rest ...) body ...)))))\n"
                  "(write (ml " (parend (reverse binds)) " (list "
                  (let ((ns (reverse names))) (if (null? ns) "'ok" (sjoin " " ns))) ")))(newline)\n")
                (string-append "let* k=" (number->string k)))
          (let* ((nm (list-ref vars i))
                 (val (if (or (not prev) (rand-bool rng)) (datum rng)
                          (string-append "(+ " prev " 1)")))
                 (bind (string-append "(" nm " " val ")")))
            (loop (+ i 1) nm (cons bind binds) (cons nm names)))))))

(define (shape-quasi-splice rng)     ; quasiquote with unquote-splicing of ellipsis
  (let ((xs (group rng 0 5)))
    (cons (string-append (defmac (list (cons "(_ (a ...))" "`(start ,@(list a ...) end)")))
                         "(write (m " (parend xs) "))(newline)\n")
          (string-append "quasi-splice |a|=" (number->string (length xs))))))

(define (shape-nested-gen rng)       ; macro-generating macro threading a token
  (let* ((tok (rand-choice rng (list "hello" "tok" "zzz"))) (arg (datum rng)))
    (cons (string-append
            "(define-syntax gen\n  (syntax-rules ()\n"
            "    ((_ mac t)\n     (define-syntax mac\n"
            "       (syntax-rules () ((_ x) (list 't x)))))))\n"
            "(gen m1 " tok ")\n(write (m1 " arg "))(newline)\n")
          (string-append "nested-gen tok=" tok))))

(define (shape-pair-ellipsis rng)    ; ellipsis over a 2-element sub-pattern
  (let* ((n (rand-int rng 0 4))
         (pairs (repeat-n n (lambda () (let* ((k (datum rng)) (v (datum rng))) (cons k v))))))
    (cons (string-append (defmac (list (cons "(_ (k v) ...)" "(list (list k v) ...)")))
                         "(write (m " (sjoin " " (map (lambda (p)
                            (string-append "(" (car p) " " (cdr p) ")")) pairs)) "))(newline)\n")
          (string-append "pair-ellipsis n=" (number->string n)))))

(define (shape-wildcard rng)         ; underscore wildcards are ignored, not bound
  (let* ((a (datum rng)) (mid (datum rng)) (b (datum rng)))
    (cons (string-append (defmac (list (cons "(_ a _ b)" "(list a b)")))
                         "(write (m " a " " mid " " b "))(newline)\n")
          "wildcard-mid")))

(define (shape-arity-error rng)      ; deliberate arity mismatch -> error parity probe
  (let* ((d1 (datum rng)) (d2 (datum rng)) (d3 (datum rng))
         (extra (rand-choice rng (list '() (list d1) (list d2 d3))))
         (two? (rand-bool rng))
         (args (if two? (let* ((x (datum rng)) (y (datum rng))) (append (list x y) extra))
                   (list (datum rng)))))
    (cons (string-append (defmac (list (cons "(_ a b)" "(list a b)")))
                         "(write (m " (sjoin " " args) "))(newline)\n")
          (string-append "arity-error argc=" (number->string (length args))))))

(define shapes
  (list shape-zip shape-flatten shape-transpose shape-fold shape-broadcast
        shape-fixed-tail shape-vector shape-dotted shape-recursive-or
        shape-let-star shape-quasi-splice shape-nested-gen
        shape-pair-ellipsis shape-wildcard shape-arity-error))

;; ---- the fuzz loop -------------------------------------------------------------

;; N/SEED default to the old `fuzz.py --n 30 --seed 1`; override via env (interpreters
;; reject extra argv, so CI's larger run sets FUZZ_N rather than a flag).
(define (env-int name default)
  (let* ((e (get-environment-variable name)) (n (and e (string->number e))))
    (if (and n (integer? n) (> n 0)) n default)))
(define N (env-int "FUZZ_N" 30))
(define SEED (env-int "FUZZ_SEED" 1))
(define rng (make-rng SEED))
(define scratch "fuzz-scratch.scm")

(display "macro fuzzer: n=") (display N) (display " seed=") (display SEED)
(display "  [cross-port: pyScheme vs cppScheme2]") (newline)

(define findings 0)
(let loop ((i 0))
  (when (< i N)
    (let* ((shape (rand-choice rng shapes))
           (sn (shape rng))
           (src (car sn))
           (note (cdr sn)))
      (when (file-exists? scratch) (delete-file scratch))   ; fresh file each program
      (call-with-output-file scratch (lambda (p) (write-string src p)))
      (let ((py (run-case py-argv scratch))
            (cpp (run-case cpp-argv scratch))
            (ch (run-chibi scratch)))            ; #f unless oracle?
        (cond
          ((not (behaves-like? py cpp))
           (set! findings (+ findings 1))
           (display "  DIVERGE [") (display (divergence-kind py cpp)) (display "]  ")
           (display note) (newline)
           (display "    --- program ---") (newline) (display src) (newline)
           (show "pyScheme" py) (show "cppScheme2" cpp)
           (when ch (show-chibi ch)
                 (display "          --> ") (display (adjudicate py cpp ch)) (newline)))
          ((and ch (not (matches-oracle? py ch)))
           (set! findings (+ findings 1))
           (display "  SHARED  ") (display note) (display "  (ports agree, differ from chibi)") (newline)
           (display "    --- program ---") (newline) (display src) (newline)
           (show "py & cpp" py) (show-chibi ch)))))
    (loop (+ i 1))))
(when (file-exists? scratch) (delete-file scratch))

(newline)
(display "macro fuzzer: ") (display N) (display " programs, ")
(display findings) (display " divergence(s)") (newline)
(exit (if (= findings 0) 0 1))
