(define-library (demo thing)
  ;; Library shell for the native plugin guard.  The colocated thing.dll (a copy of
  ;; example_plugin.dll, staged at test time) registers native-answer/native-hello
  ;; into the GLOBAL env via cppscheme2_plugin_init when this library is imported,
  ;; so they are NOT exported here (exporting an undefined name would error).
  (import (scheme base))
  (begin))
