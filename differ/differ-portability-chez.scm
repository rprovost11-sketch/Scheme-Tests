;;; differ-portability-chez.scm -- Chez Scheme entry point for the differ-core
;;; portability test.  Bare Chez has NO (scheme base) library and its native
;;; define-record-type is R6RS (incompatible syntax), so we cannot use the R7RS
;;; differ-portability.scm wrapper.  Instead supply a tiny vector-backed R7RS
;;; define-record-type shim, then include the SAME shared body -- which runs in Chez's
;;; default top-level, where car / cons / display / write / vector-ref / ... are all
;;; native.  (The differ never calls `error` on the passing path, so Chez's R6RS
;;; `error` arity is irrelevant here.)
;;;
;;; Run (cwd = scheme-tests/differ):  scheme --script differ-portability-chez.scm

;; Recursively define each (field accessor) spec as vector-ref at the next index
;; (position 0 holds the type tag).  The differ's records have no setters, so 2-element
;; specs only.
(define-syntax drt-accessors
  (syntax-rules ()
    ((_ _idx) (if #f #f))
    ((_ idx (fname accessor) rest ...)
     (begin (define (accessor x) (vector-ref x idx))
            (drt-accessors (+ idx 1) rest ...)))))

;; A record is #(tag field-val ...); the tag is the (interned) type-name symbol, so
;; eq? distinguishes record types.  ASSUMES the constructor lists every field in
;; field-spec order -- true for every differ record (<interp>, <cycle>, <verdict>).
(define-syntax define-record-type
  (syntax-rules ()
    ((_ tname (cname cfield ...) pname spec ...)
     (begin
       (define (cname cfield ...) (vector 'tname cfield ...))
       (define (pname x)
         (and (vector? x) (> (vector-length x) 0) (eq? (vector-ref x 0) 'tname)))
       (drt-accessors 1 spec ...)))))

(include "differ-portability-body.scm")
