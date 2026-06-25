;;; parse-log-validate.scm -- prove the pure-Scheme parse-log.scm byte-for-byte
;;; equivalent to the NATIVE primitives over the whole real .log corpus.
;;;
;;; For every .log file under the corpus dirs it runs BOTH:
;;;   (parse-log-file path)         [native primitive, the oracle]
;;;   (scheme-parse-log-file path)  [pure Scheme, parse-log.scm]
;;; and asserts the two entry lists are equal?.  Then, for every parsed entry, it
;;; drives several (actual, timed-out?) combinations through BOTH
;;;   (log-match-detail ...)        [native]
;;;   (scheme-log-match-detail ...) [pure Scheme]
;;; and asserts the per-channel verdicts agree.  That exercises the alternative
;;; (' or ==> '), %any-error%, %optional-error%, timeout and per-channel paths
;;; against the real corpus of expected strings.
;;;
;;; Exit 0 iff Scheme == native EVERYWHERE.  Run from the differ dir (default), or
;;; set DIFFER_HOME (parse-log.scm location) and CORPUS_ROOT (log-tests root):
;;;   cd scheme-tests/differ
;;;   <interp> -L D:/SWDEV/Languages/Lisp/SRFI parse-log-validate.scm

(import (scheme base) (scheme char) (scheme file) (scheme write)
        (scheme process-context) (srfi 152))

(define differ-home (or (get-environment-variable "DIFFER_HOME") "."))
(load (string-append differ-home "/parse-log.scm"))

(define corpus-root (or (get-environment-variable "CORPUS_ROOT") "../log-tests"))
(define corpus-dirs
  '("feature-tests" "regression-tests" "R7RS-Compliance-Tests" "srfi-tests"))

(define (log-file? name)
  (let ((n (string-length name)))
    (and (>= n 4) (string=? (substring name (- n 4) n) ".log"))))

(define (path-join . parts)
  (let loop ((ps (cdr parts)) (acc (car parts)))
    (if (null? ps) acc (loop (cdr ps) (string-append acc "/" (car ps))))))

;; --- tallies ---
(define files-checked 0)
(define entries-checked 0)
(define parse-mismatches 0)
(define match-checks 0)
(define match-mismatches 0)

(define (show . xs) (for-each display xs) (newline))

;; Report the first point two entry lists diverge (index + the two entries).
(define (report-parse-divergence path nat sch)
  (set! parse-mismatches (+ parse-mismatches 1))
  (show "PARSE MISMATCH: " path)
  (let loop ((i 0) (a nat) (b sch))
    (cond
      ((and (null? a) (null? b))
       (show "  (lists equal element-wise but equal? disagreed -- investigate)"))
      ((null? a) (show "  native ran out at entry " i "; scheme has more"))
      ((null? b) (show "  scheme ran out at entry " i "; native has more"))
      ((equal? (car a) (car b)) (loop (+ i 1) (cdr a) (cdr b)))
      (else
       (show "  first differing entry index " i ":")
       (write (list 'native (car a))) (newline)
       (write (list 'scheme (car b))) (newline)))))

;; The (actual-output actual-retval actual-error timed-out?) probes applied to
;; each entry's expected (output retval error).  Covers self-match, a perturbed
;; mismatch, an empty-actual case, and a timeout.
(define (match-probes eo er ee)
  (list
   (list eo er ee #f)                                  ; exact self-match
   (list (string-append eo "X") (string-append er "X") ; perturbed
         (if (string=? ee "") "boom" "") #f)
   (list "" "" "" #f)                                  ; all-empty actual
   (list eo er ee #t)))                                ; timeout

(define (check-match eo er ee)
  (for-each
   (lambda (probe)
     (let* ((ao (list-ref probe 0)) (ar (list-ref probe 1))
            (ae (list-ref probe 2)) (to (list-ref probe 3))
            (nat (log-match-detail        eo er ee ao ar ae to))
            (sch (scheme-log-match-detail eo er ee ao ar ae to)))
       (set! match-checks (+ match-checks 1))
       (unless (equal? nat sch)
         (set! match-mismatches (+ match-mismatches 1))
         (show "MATCH MISMATCH on probe " probe)
         (show "  exp out/ret/err = " (list eo er ee))
         (show "  native=" nat "  scheme=" sch))))
   (match-probes eo er ee)))

(define (check-file path)
  (let ((nat (parse-log-file path))
        (sch (scheme-parse-log-file path)))
    (set! files-checked (+ files-checked 1))
    (if (equal? nat sch)
        (set! entries-checked (+ entries-checked (length nat)))
        (report-parse-divergence path nat sch))
    ;; match-semantics differential over the (native) entries
    (for-each
     (lambda (e)
       (set! entries-checked entries-checked)            ; counted above on success
       (check-match (list-ref e 1) (list-ref e 2) (list-ref e 3)))
     nat)))

(for-each
 (lambda (dir)
   (let ((d (path-join corpus-root dir)))
     (for-each
      (lambda (name)
        (when (log-file? name)
          (check-file (path-join d name))))
      (directory-files d))))
 corpus-dirs)

(newline)
(show "=== parse-log Scheme-vs-native validation ===")
(show "files=" files-checked
      "  entries=" entries-checked
      "  parse-mismatches=" parse-mismatches)
(show "match-checks=" match-checks "  match-mismatches=" match-mismatches)
(let ((ok (and (= parse-mismatches 0) (= match-mismatches 0))))
  (show (if ok "ALL IDENTICAL -- pure Scheme == native everywhere"
            "DIVERGENCE -- see above"))
  (exit (if ok 0 1)))
