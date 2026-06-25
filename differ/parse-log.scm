;;; parse-log.scm -- pure-Scheme reimplementation of the native .log session-log
;;; parser and match semantics, part of the path to SELF-HOSTING the differ.
;;;
;;; ADDITIVE: the native primitives (parse-log-file) / (log-match?) /
;;; (log-match-detail) stay in place.  These Scheme procedures are an ALTERNATIVE
;;; the differ can switch to, validated byte-for-byte against the native versions
;;; over the whole real .log corpus -- see parse-log-validate.scm.
;;;
;;; LOADED (not imported), mirroring differ.scm, AFTER the loader's own
;;;   (import (scheme base) (scheme char) (scheme file) (srfi 152))
;;; Needs (srfi 152) for string ops, so the loader must be launched with
;;;   -L <SRFI repo root>   (e.g. -L D:/SWDEV/Languages/Lisp/SRFI)
;;; so (srfi 152) resolves -- exactly like the differ-srfi suite.
;;;
;;; REFERENCE (the oracle these must match): the free-standing native parse_log /
;;; log_match in cpp src/Utils.cpp + py pyscheme/Utils.py (the two are kept
;;; behaviourally identical).  Entry shape matches native EXACTLY:
;;;   (input output retval error fold-case?)
;;; with output/retval/error right-stripped and input kept verbatim.
;;;
;;; Exported by top-level define (no library wrapper, like differ.scm):
;;;   (scheme-parse-log text)        -> list of 5-element entry lists
;;;   (scheme-parse-log-file path)   -> read PATH as text, then scheme-parse-log
;;;   (scheme-log-match? eo er ee ao ar ae timed-out?)        -> boolean
;;;   (scheme-log-match-detail eo er ee ao ar ae timed-out?)  -> (oo? ro? eo?)

;; ---- whitespace handling matching native _u_rstrip / _u_strip -----------------
;; Native strips EXACTLY space, tab, carriage-return, newline (not the broader
;; char-whitespace? set), so use an explicit predicate rather than srfi-152's
;; default char-whitespace?.
(define (%plog-ws? c)
  (or (char=? c #\space) (char=? c #\tab)
      (char=? c #\return) (char=? c #\newline)))

(define (%plog-rstrip s) (string-trim-right s %plog-ws?))
(define (%plog-strip  s) (string-trim-both  s %plog-ws?))

;; ---- read a file as text -------------------------------------------------------
;; Read every character of PATH into one string.  The native parse-log-file reads
;; via a TEXT-mode stream (cpp std::ifstream / py universal-newline open), so CRLF
;; is normalised to LF before parsing; %plog-split-lines does the same here, so it
;; does not matter whether this port's textual port already translates line endings.
(define (%plog-read-file path)
  (let ((p (open-input-file path)))
    (let loop ((acc '()))
      (let ((c (read-char p)))
        (if (eof-object? c)
            (begin (close-input-port p) (list->string (reverse acc)))
            (loop (cons c acc)))))))

;; ---- split into lines, keeping the trailing newline ----------------------------
;; Mirrors Python splitlines(keepends=True) over '\n' AFTER the CRLF->LF that the
;; native text-mode read performs: a '\r' immediately before a '\n' is dropped, and
;; every produced line ends in a single '\n' (except a final line with no newline).
(define (%plog-split-lines text)
  (let ((n (string-length text)))
    (let loop ((i 0) (start 0) (lines '()))
      (cond
        ((>= i n)
         (reverse (if (> i start)
                      (cons (substring text start i) lines)   ; final, no newline
                      lines)))
        ((char=? (string-ref text i) #\newline)
         (let* ((cr? (and (> i start)
                          (char=? (string-ref text (- i 1)) #\return)))
                (end (if cr? (- i 1) i))
                (line (string-append (substring text start end) "\n")))
           (loop (+ i 1) (+ i 1) (cons line lines))))
        (else (loop (+ i 1) start lines))))))

;; ---- the parser ----------------------------------------------------------------
;; Direct port of native parse_log (cpp Utils.cpp / py Utils.py): each entry begins
;; with a '>>> ' line; '... ' lines continue the input; lines before '==> ' are
;; output; '==> ' gives the return value (possibly multi-line, ';' lines folded back
;; into the input); '%%% ' lines are the error; '#!fold-case' / '#!no-fold-case'
;; toggle the per-entry fold-case flag.
(define (scheme-parse-log text)
  (define lv (list->vector (%plog-split-lines text)))
  (define n (vector-length lv))
  (define (line i) (vector-ref lv i))
  (define (llen i) (string-length (line i)))
  (define (sw i pfx) (string-prefix? pfx (line i)))        ; srfi152 order: (prefix s)
  (define (rstrip-eq i expected) (string=? (%plog-rstrip (line i)) expected))
  (define idx 0)
  (define fold-case #f)
  (define entries '())
  (let outer ()
    (when (< idx n)
      ;; skip lines up to the next '>>> ', honouring fold-case directives
      (let skip ()
        (when (and (< idx n) (not (sw idx ">>> ")))
          (cond ((rstrip-eq idx "#!fold-case")    (set! fold-case #t))
                ((rstrip-eq idx "#!no-fold-case")  (set! fold-case #f)))
          (set! idx (+ idx 1))
          (skip)))
      (when (< idx n)
        (let ((entry-fc fold-case)
              (expr   (substring (line idx) 4 (llen idx)))
              (output "")
              (retval "")
              (errm   ""))
          (set! idx (+ idx 1))
          ;; '... ' continuation lines append to the input
          (let cont ()
            (when (and (< idx n) (sw idx "... "))
              (set! expr (string-append expr (substring (line idx) 4 (llen idx))))
              (set! idx (+ idx 1))
              (cont)))
          ;; optional bare '...' marker (old-style multi-line)
          (when (and (< idx n) (rstrip-eq idx "...") (not (sw idx "... ")))
            (set! idx (+ idx 1)))
          ;; output lines (anything before a marker)
          (let outl ()
            (when (< idx n)
              (cond
                ((or (sw idx "==> ") (rstrip-eq idx "==>")) #f)
                ((or (sw idx "... ") (sw idx ">>> ") (sw idx "%%% ")) #f)
                (else
                 (set! output (string-append output (line idx)))
                 (set! idx (+ idx 1))
                 (outl)))))
          ;; '==> ' return value (possibly multi-line; ';' lines fold into input)
          (when (and (< idx n) (or (sw idx "==> ") (rstrip-eq idx "==>")))
            (when (> (llen idx) 4)
              (set! retval (substring (line idx) 4 (llen idx))))
            (set! idx (+ idx 1))
            (let retl ()
              (when (< idx n)
                (cond
                  ((or (sw idx "==> ") (rstrip-eq idx "==>")) #f)
                  ((or (sw idx "... ") (sw idx ">>> ") (sw idx "%%% ")) #f)
                  ((sw idx "#!") #f)                        ; fold-case directive
                  (else
                   (let ((l (line idx)))
                     (if (and (> (string-length l) 0) (char=? (string-ref l 0) #\;))
                         (set! expr (string-append expr l))
                         (set! retval (string-append retval l))))
                   (set! idx (+ idx 1))
                   (retl))))))
          ;; '%%% ' error lines
          (when (and (< idx n) (sw idx "%%% "))
            (set! errm (substring (line idx) 4 (llen idx)))
            (set! idx (+ idx 1))
            (let errl ()
              (when (and (< idx n) (sw idx "%%% "))
                (set! errm (string-append errm (substring (line idx) 4 (llen idx))))
                (set! idx (+ idx 1))
                (errl))))
          ;; commit (only if the input is non-empty, like native)
          (when (> (string-length expr) 0)
            (set! entries
                  (cons (list expr
                              (%plog-rstrip output)
                              (%plog-rstrip retval)
                              (%plog-rstrip errm)
                              entry-fc)
                        entries)))))
      (outer)))
  (reverse entries))

(define (scheme-parse-log-file path)
  (scheme-parse-log (%plog-read-file path)))

;; ---- match semantics -----------------------------------------------------------
;; Direct port of native match_retval / log_match.

;; A retval matches if it equals ANY of the ' or ==> '-separated alternatives
;; (each trimmed).  Mirrors cpp log_match_retval, which strips every alternative
;; (including the single-alternative case) before comparing.
(define (%plog-match-retval actual expected)
  (let loop ((parts (string-split expected " or ==> ")))
    (cond ((null? parts) #f)
          ((string=? actual (%plog-strip (car parts))) #t)
          (else (loop (cdr parts))))))

;; Per-channel match triple (output-ok? retval-ok? error-ok?):
;;   * a timeout fails every channel;
;;   * '%optional-error%' (R7RS "it is an error") passes everything;
;;   * '*' / '%any-error%' accept any non-empty actual error;
;;   * otherwise an exact (right-stripped) compare per channel.
(define (scheme-log-match-detail eo er ee ao ar ae timed-out?)
  (let ((exp-out (%plog-rstrip eo))
        (act-out (%plog-rstrip ao)))
    (cond
      (timed-out? (list #f #f #f))
      ((string-prefix? "%optional-error%" ee) (list #t #t #t))
      (else
       (let ((error-ok
              (if (or (string=? ee "*") (string-prefix? "%any-error%" ee))
                  (> (string-length ae) 0)
                  (string=? ae ee)))
             (retval-ok (%plog-match-retval ar er))
             (output-ok (string=? act-out exp-out)))
         (list output-ok retval-ok error-ok))))))

(define (scheme-log-match? eo er ee ao ar ae timed-out?)
  (let ((d (scheme-log-match-detail eo er ee ao ar ae timed-out?)))
    (and (car d) (cadr d) (car (cddr d)))))
