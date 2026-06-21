;;; plugin-import.scm -- SRFI-64 guard for the native .dll-via-import path.
;;;
;;; cppScheme2-ONLY: pyScheme plugins are .py (not colocated .dll), and the loader's
;;; native-plugin search is .dll-hardcoded (evaluator.cpp) -> Windows in practice.
;;;
;;; Replaces the old plugin-import-test.sh -- instead of bash (mktemp/cygpath/cp) it
;;; stages the plugin from inside Scheme: it locates the running exe via the
;;; cppScheme2 extension (interpreter-executable-path), copies example_plugin.dll
;;; (built beside the exe) to demo/thing.dll beside the committed demo/thing.sld
;;; using pure R7RS binary ports, then imports (demo thing) and asserts the native
;;; primitive answers 42 -- the one test that exercises load_plugin / FRAME_ENSURE_LOADED.
;;;
;;; Run (cpp only; -L makes (srfi 64) and (demo thing) resolve):
;;;   cppscheme2 -L <repo>/scheme-tests/application-tests/plugin-import -L <repo>/SRFI plugin-import.scm

(import (scheme base) (scheme file) (srfi 64))

;; Directory portion of a path (handles both / and \ separators; the exe path is
;; backslash-form on Windows).
(define (dir-of path)
  (let loop ((i (- (string-length path) 1)))
    (cond ((< i 0) ".")
          ((let ((c (string-ref path i))) (or (char=? c #\/) (char=? c #\\)))
           (substring path 0 i))
          (else (loop (- i 1))))))

;; The -L directory that holds our committed demo/thing.sld (we stage thing.dll
;; beside it so (import (demo thing)) finds the colocated plugin).
(define (find-fixture-dir paths)
  (cond ((null? paths) #f)
        ((file-exists? (string-append (car paths) "/demo/thing.sld")) (car paths))
        (else (find-fixture-dir (cdr paths)))))

(define (copy-binary-file src dst)
  (let ((in (open-binary-input-file src))
        (out (open-binary-output-file dst)))
    (let loop ()
      (let ((bv (read-bytevector 65536 in)))
        (if (eof-object? bv)
            (begin (close-port in) (close-port out))
            (begin (write-bytevector bv out) (loop)))))))

(define exe (interpreter-executable-path))
(define fixture-dir (find-fixture-dir (current-library-path)))
(define plugin-src (and (string? exe) (string-append (dir-of exe) "/example_plugin.dll")))

(test-begin "plugin-import")

(test-assert "interpreter-executable-path returns a path" (string? exe))
(test-assert "fixture demo/ dir is on the library path" (string? fixture-dir))
(test-assert "example_plugin.dll present beside the exe"
  (and plugin-src (file-exists? plugin-src)))

;; Stage example_plugin.dll as demo/thing.dll beside the committed thing.sld.
(when (and plugin-src fixture-dir (file-exists? plugin-src))
  (copy-binary-file plugin-src (string-append fixture-dir "/demo/thing.dll")))

;; Importing (demo thing) loads thing.dll, whose init registers native-answer into
;; the global env (the .sld is just the library shell).
(import (demo thing))

(test-equal "native-answer returns 42" 42 (native-answer))

(test-end "plugin-import")
