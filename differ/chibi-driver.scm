;;; chibi-driver.scm -- subprocess driver for the differ's CHIBI conformance subject.
;;;
;;; Chibi-Scheme is the R7RS reference oracle but has no eval-cycle primitive, so it
;;; can't use sibling-driver.scm.  This driver speaks the SAME stdin/stdout protocol
;;; as sibling-driver (so the differ's make-sibling-interp drives it unchanged) but
;;; captures a cycle's outcome with portable R7RS only: it reads one
;;; (input-string fold-case?) form per entry from stdin, evaluates the input's forms
;;; in ONE persistent (interaction-environment) (defines accumulate across cycles),
;;; capturing the cycle's display output by rebinding current-output-port, the return
;;; value(s) via write, and any error via guard; then writes one
;;; (output retval error timed-out?) form per cycle to stdout -- exactly the 4-tuple
;;; the parent's parse-driver-output reads back.  The capture logic mirrors the proven
;;; chibi_diff.py driver.  error = "" means no error (so cycle-errored? is #f); a
;;; chibi stderr warning about an unported lib lands on stderr and is ignored.
;;;
;;; Run by the conformance harness as:  chibi-scheme -I <lib> chibi-driver.scm  < specs

(import (scheme base) (scheme write) (scheme eval) (scheme repl) (scheme read)
        (scheme char) (scheme inexact) (scheme complex) (scheme cxr) (scheme lazy)
        (scheme file) (scheme process-context) (scheme case-lambda) (scheme load))

(define ie (interaction-environment))

(define (obj->string x)
  (let ((p (open-output-string))) (write x p) (get-output-string p)))

(define (read-all str)
  (let ((p (open-input-string str)))
    (let loop ((acc '()))
      (let ((x (read p)))
        (if (eof-object? x) (reverse acc) (loop (cons x acc)))))))

(define (err->string e)
  (if (error-object? e)
      (let ((irr (error-object-irritants e)))
        (string-append (error-object-message e)
                       (if (null? irr) "" (string-append " " (obj->string irr)))))
      (obj->string e)))

(define (rstrip s)
  (let loop ((i (string-length s)))
    (if (and (> i 0)
             (let ((c (string-ref s (- i 1))))
               (or (char=? c #\space) (char=? c #\tab)
                   (char=? c #\newline) (char=? c #\return))))
        (loop (- i 1))
        (substring s 0 i))))

(let loop ()
  (let ((spec (read)))
    (unless (eof-object? spec)
      (let* ((input (car spec))
             (fc    (cadr spec))
             (src   (if fc (string-append "#!fold-case\n" input) input))
             (sp    (open-output-string))
             (errored #f)
             (errmsg  "")
             (retval  ""))
        (guard (e (#t (set! errored #t) (set! errmsg (err->string e))))
          (let ((vals (parameterize ((current-output-port sp))
                        (let lp ((fs (read-all src)) (last '()))
                          (if (null? fs)
                              last
                              (lp (cdr fs)
                                  (call-with-values (lambda () (eval (car fs) ie)) list)))))))
            (set! retval (rstrip (apply string-append
                                        (map (lambda (v) (string-append (obj->string v) " ")) vals))))))
        (write (list (get-output-string sp)
                     (if errored "" retval)
                     (if errored errmsg "")
                     #f))
        (newline))
      (loop))))
