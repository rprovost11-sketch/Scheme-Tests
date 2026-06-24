;;; differ-portability.scm -- prove the differ's pure-R7RS classification CORE runs
;;; identically on ANY R7RS interpreter, not just the cpp/py ports it ships inside.
;;;
;;; This is the R7RS entry point: import (scheme base)/(scheme write) -- which supply
;;; define-record-type and the basic procedures -- then include the shared test body.
;;; The body splices the REAL differ.scm and exercises only the pure classification
;;; core with mock interpreters (no extension primitive is ever called).  It prints
;;; ONE canonical line; differ-portability-run.scm launches this on every available
;;; interpreter and checks they all print the SAME line, byte for byte.
;;;
;;; Run by hand (cwd = scheme-tests/differ):
;;;   <cppScheme2/pyScheme>     differ-portability.scm
;;;   gosh -r7                  differ-portability.scm
;;;   chibi-scheme -I <lib>     differ-portability.scm
;;;   scheme --script           differ-portability-chez.scm   (bare Chez: shim wrapper)

(import (scheme base) (scheme write))
(include "differ-portability-body.scm")
