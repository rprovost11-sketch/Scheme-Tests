;;; test-suites.scm -- the test-suite REGISTRY (single source of truth, backlog #9/#7).
;;;
;;; This is DATA, not code: a sequence of top-level (suite ...) S-expressions read
;;; with the interpreter's OWN reader.  The listener (]suites) reads it in-process
;;; on BOTH ports -- so adding a test here is the ONE place it needs to appear; it
;;; then shows up in `]suites list`, runs via `]suites <name>` / `]suites all`, and
;;; (because Cherry renders its checklist from `]suites list`) appears in Cherry too.
;;; Nothing about the suites is hardcoded in the listener any more: the .log
;;; subdirectories, the property-test paths, and the external-tool commands all live
;;; here.
;;;
;;; SCHEMA   (suite "<name>" (key value ...) ...)
;;;   Keys (a suite has the ones its kind needs):
;;;     (kind  log | scheme | external)
;;;       log      -- a directory of .log session-transcript suites, run IN-PROCESS
;;;                   by this interpreter (fresh reboot per file).  Needs (path DIR).
;;;       scheme   -- a single .scm program run IN-PROCESS by this interpreter in a
;;;                   fresh env; pass = the SRFI-64 summary reports 0 failed.
;;;                   Needs (path FILE); (libs DIR ...) for any -L load paths.
;;;       external -- a separate program the runner SPAWNS (cannot be in-process:
;;;                   a compiled exe, a two-interpreter differential, a Python tool).
;;;                   Needs (run PROG ARG ...); optional (cwd DIR) (pass COND).
;;;     (alias NAME ...)        short alternate name(s); `]suites mc` == the full name.
;;;     (categories CAT ...)    group labels; `]suites metamorphic` runs every suite
;;;                             so categorised.  Categories are just data -- to make a
;;;                             new group, add its string to the relevant suites.
;;;     (variant "NAME" PROP ...)  an alternative parameterisation that OVERRIDES the
;;;                             listed props (e.g. (variant "slow" (tco-soak ...))).
;;;                             The base props are the implicit "quick" variant.  A
;;;                             `-NAME` suffix on any selector token picks it:
;;;                             `compliance-slow`, `all-slow` (slow where a suite has
;;;                             it, base otherwise), `metamorphic-slow`.  No suffix =>
;;;                             quick, so `all` == `all-quick`.  If a variant overrides
;;;                             (ports ...) and the current port isn't included, that
;;;                             suite falls back to its base run instead of the variant.
;;;     (ports both | py | cpp)         which interpreter(s) it applies to; default both
;;;     (desc  "one-line description")  shown by `]suites list`
;;;     (pass  exit-0 | (grep "REGEX")) external pass condition; default exit-0
;;;     (tco-soak N)                    log/compliance only: TCO iteration count
;;;
;;;   TOKEN RESOLUTION for `]suites <token> ...`:  suite name -> alias -> category.
;;;   Names and aliases are unique (one suite); a category names many.  `all` is NOT
;;;   special: it is an implicit category the runner adds to EVERY suite, so
;;;   `]suites all` is ordinary category resolution (don't name a suite/alias `all`).
;;;   `list` is the one reserved action token -- it DISPLAYS the catalog (it runs
;;;   nothing), so it likewise may not be a suite name/alias/category.
;;;
;;;   PATHS are relative to the scheme-tests root (this file's directory); use ../
;;;   for sibling repos (SRFI, 4CPPScheme2).  Placeholders the runner substitutes in
;;;   an external (run ...): {interp} = this interpreter's own launch invocation.
;;;
;;;   Current categories:  battery (the .log suites) · metamorphic (the 5 generators)
;;;                        · property (metamorphic + known-open-bugs) · tools (external)

;; ---- Tier 1: .log session-transcript batteries (in-process) ----------------
(suite "feature"
  (kind       log)
  (alias      "f" "feat")
  (categories battery)
  (ports      both)
  (path       "log-tests/feature-tests")
  (desc       "R7RS feature tests (.log session transcripts)"))

(suite "compliance"
  (kind       log)
  (alias      "c" "compl")
  (categories battery)
  (ports      both)
  (path       "log-tests/R7RS-Compliance-Tests")
  (tco-soak   100000)
  ;; -slow = the cppScheme2-only high-N TCO soak (a generational-GC stress run,
  ;; iteration count calibrated to the machine).  pyScheme has no custom GC, so
  ;; the slow variant is cpp-only; on pyScheme `compliance-slow`/`all-slow` falls
  ;; back to the base (quick) run.
  (variant "slow" (ports cpp) (tco-soak calibrate))
  (desc       "R7RS-small compliance tests (+ bounded-space TCO soak)"))

(suite "regression"
  (kind       log)
  (alias      "r" "reg")
  (categories battery)
  (ports      both)
  (path       "log-tests/regression-tests")
  (desc       "regression tests pinning previously-fixed bugs"))

;; ---- Tier 1: SRFI-64 property / metamorphic suites (in-process) -------------
(suite "metamorphic-numbers"
  (kind       scheme)
  (alias      "mn" "mnum")
  (categories metamorphic property)
  (ports      both)
  (path       "application-tests/property-tests/metamorphic-numbers.scm")
  (libs       "../SRFI")
  (desc       "numeric-tower property tester (feature-detects cpp bignum-rational reader)"))

(suite "metamorphic-datums"
  (kind       scheme)
  (alias      "md" "mdat")
  (categories metamorphic property)
  (ports      both)
  (path       "application-tests/property-tests/metamorphic-datums.scm")
  (libs       "../SRFI")
  (desc       "datum write/read round-trip property tester"))

(suite "metamorphic-compare"
  (kind       scheme)
  (alias      "mc" "mcmp")
  (categories metamorphic property)
  (ports      both)
  (path       "application-tests/property-tests/metamorphic-compare.scm")
  (libs       "../SRFI")
  (desc       "total-order law property tester for the comparison operators"))

(suite "metamorphic-strings"
  (kind       scheme)
  (alias      "ms" "mstr")
  (categories metamorphic property)
  (ports      both)
  (path       "application-tests/property-tests/metamorphic-strings.scm")
  (libs       "../SRFI")
  (desc       "string-operation property tester"))

(suite "metamorphic-eval"
  (kind       scheme)
  (alias      "me" "meval")
  (categories metamorphic property)
  (ports      both)
  (path       "application-tests/property-tests/metamorphic-eval.scm")
  (libs       "../SRFI")
  (desc       "evaluator-invariant property tester"))

(suite "known-open-bugs"
  (kind       scheme)
  (alias      "kob")
  (categories property)
  (ports      both)
  (path       "application-tests/property-tests/known-open-bugs.scm")
  (libs       "../SRFI")
  (desc       "SRFI-64 test-expect-fail pins for the parked known-open bugs"))

;; ---- Tier 2: external tools (spawned; not in-process by nature) -------------
(suite "cli-tests"
  (kind       external)
  (alias      "cli")
  (categories tools)
  (ports      both)
  ;; cwd = this dir so the runner reaches the committed fixture tests-root runfix/.
  ;; No shell: the runner relaunches the interpreter via (interpreter-argv) +
  ;; run-process and checks exit code + captured output directly.
  (cwd        "cli-tests")
  (run        "{interp}" "cli-tests.scm")
  (pass       exit-0)
  (desc       "process-boundary tests (argv, exit codes, stdin, .run reports) -- in-process, no shell"))

(suite "cross-port"
  (kind       external)
  (alias      "xp" "xport")
  (categories tools)
  ;; py-hosted: the differential launches BOTH ports via run-process; the py child
  ;; needs the pyscheme package importable, which works because the listener sets
  ;; PYTHONPATH for the suite and run-process children inherit it.  cpp is reached
  ;; by a known relative path.  The comparison is symmetric, so one host suffices.
  (ports      py)
  (cwd        "cross-port-tests")
  (run        "{interp}" "diff.scm")
  (pass       exit-0)
  (desc       "cpp-vs-py differential over syntax-rules cases (in-process driver; no python)"))

(suite "fuzz-smoke"
  (kind       external)
  (alias      "fuzz")
  (categories tools)
  (ports      py)            ; py-hosted, same as cross-port (PYTHONPATH for the py child)
  (cwd        "cross-port-tests")
  (run        "{interp}" "fuzz.scm")
  (pass       exit-0)
  (desc       "grammar-based syntax-rules fuzzer, cpp-vs-py differential (in-process driver; no python)"))

(suite "gc_test"
  (kind       external)
  (alias      "gc")
  (categories tools)
  (ports      cpp)
  (cwd        ".")
  (run        "../4CPPScheme2/build/Release/gc_test.exe")
  (pass       exit-0)
  (desc       "cppScheme2 generational-GC white-box unit tests"))

(suite "rat_test"
  (kind       external)
  (alias      "rat")
  (categories tools)
  (ports      cpp)
  (cwd        ".")
  (run        "../4CPPScheme2/build/Release/rat_test.exe")
  (pass       exit-0)
  (desc       "cppScheme2 numeric-tower (Rat / make_rational_mpz / bignum) white-box unit tests"))

(suite "plugin-import"
  (kind       scheme)
  (alias      "plug")
  (categories tools)
  (ports      cpp)
  (path       "application-tests/plugin-import/plugin-import.scm")
  ;; first lib dir holds demo/thing.sld (so (demo thing) resolves + the test stages
  ;; thing.dll there); second resolves (srfi 64).  No shell: the .scm locates the
  ;; exe via (interpreter-executable-path) and copies the plugin with R7RS binary ports.
  (libs       "application-tests/plugin-import" "../SRFI")
  (desc       "cppScheme2 native .dll-via-import guard (example_plugin -> native-answer => 42)"))

;; ---- application-level correctness / conformance suites (run via the interp) -
;; Programs that exercise the interpreter as an application (relational engine,
;; R7RS conformance, deep macro hygiene, benchmark correctness).  Each reports
;; pass/fail on its own (exit code or an "N passed, M failed" summary).

(suite "minikanren"
  (kind       external)
  (alias      "mk" "kanren")
  (categories application)
  (ports      both)
  (cwd        "application-tests/miniKanren-R7RS")
  (run        "{interp}" "-L" "." "test.scm")
  (pass       exit-0)
  (desc       "miniKanren (R7RS) relational-programming correctness suite"))

(suite "macro-hygiene"
  (kind       scheme)
  (alias      "mh" "macro")
  (categories application)
  (ports      both)
  (path       "application-tests/Claude-macro-tests/macro-hygiene-nested.scm")
  (desc       "deep syntax-rules hygiene acceptance battery (Group A regression guard)"))

(suite "chibi-survey"
  (kind       external)
  (alias      "chibi" "survey")
  (categories application)
  (ports      both)
  (cwd        "application-tests/Chibi-R7RS-tests")
  (run        "{interp}" "-L" "../../../SRFI" "_survey-driver.scm")
  (pass       exit-0)
  (desc       "chibi r7rs-tests.scm conformance/parity survey (form-by-form; exit 0 iff 0 failures + 0 FORMERRs)"))

(suite "ecraven"
  (kind       external)
  (alias      "ecr" "bench")
  (categories application)
  (ports      both)
  (cwd        "application-tests/ecraven-r7rs-benchmarks")
  ;; Quick path is now SHELL-FREE: the interpreter itself runs the in-process
  ;; runner (loads each self-checking benchmark into a fresh make-environment).
  ;; {interp} + cwd are set by the spawn (no shell `cd`); cwd lets benchmarks that
  ;; open relative aux inputs (cat->inputs/bib, dynamic->inputs/dynamic.data) work.
  (run        "{interp}" "correctness-inprocess.scm")
  ;; -slow = full timed cpp-vs-py DIFFERENTIAL over every benchmark, run via
  ;; run-process with a per-benchmark timeout (no shell).  py-hosted (PYTHONPATH for
  ;; the py child; cpp by relative path); on cpp `ecraven-slow` falls back to the
  ;; quick in-process base.  ECRAVEN_TIMEOUT env overrides the 60s/benchmark default.
  (variant "slow" (ports py) (run "{interp}" "correctness-slow.scm"))
  (pass       exit-0)
  (desc       "ecraven r7rs-benchmarks correctness smoke -- quick subset run in-process (no shell); -slow = full timed cpp-vs-py differential sweep"))
