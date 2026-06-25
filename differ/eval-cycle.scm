;;; eval-cycle.scm -- pure-Scheme reimplementation of the native (eval-cycle ...),
;;; STEP 4 of self-hosting the differ.
;;;
;;; (eval-cycle ...) used to be "the one genuinely host-coupled piece" of the
;;; differ's in-process host runner -- it bundled FOUR jobs in C++/Python:
;;;   1. capture standard output
;;;   2. format the return value
;;;   3. evaluate the input (the runner's checked parse->expand->analyze->cek_eval)
;;;   4. capture + format the error
;;; This file moves jobs 1, 2 and 4 into Scheme, leaving only job 3 in the host as
;;; a SMALLER primitive, (checked-eval source env [timeout]) -- so the host floor
;;; shrinks from "the whole REPL cycle" to "checked evaluation".  checked-eval runs
;;; the EXACT checked pipeline the runner uses (so malformed forms are rejected the
;;; same way, not crashed-on like the plain `eval` primitive) and, on failure,
;;; RAISES a Scheme error whose message is the runner-formatted string (class +
;;; line/col + source echo + caret).  scheme-eval-cycle therefore reproduces native
;;; eval-cycle BYTE-FOR-BYTE on all four channels, errors included.
;;;
;;; checked-eval does the irreducibly host-coupled work and RETURNS a structured
;;; result -- (values output status payload) -- so this wrapper never has to
;;; re-raise (which would graft a propagation backtrace onto the error text) nor
;;; redirect current-output-port (which leaks output from primitives like help/trace
;;; that write straight to the host output stream).  What stays in Scheme is the
;;; PRESENTATION: right-strip the output, format the value list (write / void -> "" /
;;; multiple values space-joined), and detect the timeout marker.
;;;
;;; Host primitives used (the irreducible minimum):
;;;   * checked-eval  -- the runner's checked evaluation + raw output/error capture
;;;   * write         -- value-formatting matches the runner's scheme_pretty_print
;;;
;;; ADDITIVE: the native eval-cycle primitive stays in place.  scheme-eval-cycle is
;;; the Scheme alternative; eval-cycle-validate.scm checks it byte-for-byte against
;;; the native primitive over the whole .log corpus.
;;;
;;; LOADED (not imported), like differ.scm, after the loader's own
;;;   (import (scheme base) (scheme write))
;;;
;;; Exported by top-level define:
;;;   (scheme-eval-cycle input env [timeout]) -> (values output retval error timed-out?)

;; ---- small helpers (kept dependency-light: only (scheme base)/(scheme write)) ---

;; The void / unspecified value is a singleton; the runner formats it as "".
(define %ec-void (if #f #f))
(define (%ec-void? v) (eq? v %ec-void))

(define (%ec-write-to-string v)
  (let ((sp (open-output-string)))
    (write v sp)
    (get-output-string sp)))

;; Right-strip space/tab/CR/LF, mirroring the runner's _ec_rstrip.  Only the
;; captured OUTPUT is stripped (retval/error are left verbatim, as in native).
(define (%ec-rstrip s)
  (let loop ((i (string-length s)))
    (if (and (> i 0)
             (let ((c (string-ref s (- i 1))))
               (or (char=? c #\space) (char=? c #\tab)
                   (char=? c #\return) (char=? c #\newline))))
        (loop (- i 1))
        (substring s 0 i))))

;; Naive substring test (avoids a (srfi 152) dependency here); used only to spot
;; the runner's timeout marker in a caught error message.
(define (%ec-contains? s sub)
  (let ((ls (string-length s)) (lsub (string-length sub)))
    (let loop ((i 0))
      (cond ((> (+ i lsub) ls) #f)
            ((let inner ((j 0))
               (cond ((= j lsub) #t)
                     ((char=? (string-ref s (+ i j)) (string-ref sub j)) (inner (+ j 1)))
                     (else #f)))
             #t)
            (else (loop (+ i 1)))))))

;; Format the return value(s) exactly as native does:
;;   zero values, or a single void value  -> ""
;;   otherwise                            -> the values' write forms, space-joined
(define (%ec-format-vals vals)
  (cond
    ((null? vals) "")
    ((and (null? (cdr vals)) (%ec-void? (car vals))) "")
    (else
     (let loop ((vs vals) (s "") (first #t))
       (if (null? vs)
           s
           (loop (cdr vs)
                 (string-append s (if first "" " ") (%ec-write-to-string (car vs)))
                 #f))))))

;; ---- the cycle -----------------------------------------------------------------

(define %ec-timeout-marker "Evaluation timed out.")

(define (scheme-eval-cycle input env . opt)
  (let ((timeout (if (pair? opt) (car opt) #f)))
    (call-with-values
      (lambda () (checked-eval input env timeout))
      (lambda (output status payload)
        (if (eq? status 'ok)
            (values (%ec-rstrip output) (%ec-format-vals payload) "" #f)
            ;; payload is the runner-formatted error string
            (values (%ec-rstrip output) "" payload
                    (%ec-contains? payload %ec-timeout-marker)))))))
