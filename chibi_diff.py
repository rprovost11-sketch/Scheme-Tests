#!/usr/bin/env python3
"""chibi_diff.py -- run compliance/feature .log expressions through Chibi-Scheme
(the R7RS reference oracle) and emit a *-Chibi.run file plus a console summary of
where Chibi DISAGREES with the suite's expected values.

Each .log entry's expression(s) are evaluated in a single persistent Chibi
interaction-environment per file (so defines accumulate), with per-entry output
capture and error isolation.  Values come back on stdout; Chibi's stderr warnings
(unported chibi-specific libs) are ignored.

Usage:
    python chibi_diff.py "<dir>/6.03 - Booleans.log"   # one file
    python chibi_diff.py --suite compliance            # all compliance files
"""
import os
import re
import sys
import subprocess
import tempfile
import datetime

CHIBI_DIR = r"D:/SWDEV/tools/chibi-scheme"
CHIBI_EXE = CHIBI_DIR + "/chibi-scheme.exe"
CHIBI_LIB = CHIBI_DIR + "/lib"
COMPLIANCE_DIR = r"D:/SWDEV/Languages/Lisp/scheme-tests/R7RS-Compliance-Tests"
FEATURE_DIR = r"D:/SWDEV/Languages/Lisp/scheme-tests/feature-tests"
RUNS_DIR = r"D:/SWDEV/Languages/Lisp/scheme-tests/runs"

# Markers the Chibi driver prints around each record.  Use ASCII control chars
# (record/unit separators) that never appear in normal Scheme write output.
M_REC = "\x1eR\x1e"
M_OUT = "\x1eO\x1e"
M_VAL = "\x1eV\x1e"
M_ERR = "\x1eE\x1e"
M_END = "\x1eX\x1e"


# ---------------------------------------------------------------------------
# .log parsing  (>>> expr / ... cont / expected output / ==> retval / %%% error)
# ---------------------------------------------------------------------------
class Entry:
    def __init__(self):
        self.expr = ""
        self.exp_out = ""
        self.exp_ret = None     # string after '==> ', or None
        self.exp_err = None     # string after '%%% ', or None


def parse_log(path):
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().split("\n")
    entries = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if line.startswith(">>> "):
            e = Entry()
            e.expr = line[4:]
            i += 1
            while i < n and lines[i].startswith("... "):
                e.expr += "\n" + lines[i][4:]
                i += 1
            out_lines = []
            # expected block: until next '>>> ' or EOF
            while i < n and not lines[i].startswith(">>> "):
                l = lines[i]
                if l.startswith("==> "):
                    e.exp_ret = l[4:]
                elif l.startswith("%%% "):
                    e.exp_err = l[4:]
                elif l.strip() == "" or l.startswith(";"):
                    pass  # separators / comments not part of expected output
                else:
                    out_lines.append(l)
                i += 1
            e.exp_out = "\n".join(out_lines).rstrip()
            entries.append(e)
        else:
            i += 1
    return entries


# ---------------------------------------------------------------------------
# Chibi driver generation + run
# ---------------------------------------------------------------------------
DRIVER_HEAD = r"""
(import (scheme base) (scheme write) (scheme eval) (scheme repl) (scheme read)
        (scheme char) (scheme inexact) (scheme complex) (scheme cxr) (scheme lazy)
        (scheme file) (scheme process-context) (scheme time)
        (scheme case-lambda) (scheme load))

;;;ENTRIES;;;

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

(define (emit . xs) (for-each (lambda (s) (write-string s)) xs))

(for-each
  (lambda (entry)
    (emit "MREC\n")
    (let ((sp (open-output-string)) (status 'val) (payload ""))
      (guard (e (#t (set! status 'err) (set! payload (err->string e))))
        (let ((vals (parameterize ((current-output-port sp))
                      (let loop ((fs (read-all entry)) (last '()))
                        (if (null? fs) last
                            (loop (cdr fs)
                                  (call-with-values
                                    (lambda () (eval (car fs) ie)) list)))))))
          (set! payload (apply string-append
                               (map (lambda (v) (string-append (obj->string v) " ")) vals)))))
      (emit "MOUT\n" (get-output-string sp) "\n" (if (eq? status 'err) "MERR" "MVAL") "\n"
            payload "\nMEND\n")))
  entries)
"""


def build_driver(entries):
    def lit(s):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
    body = DRIVER_HEAD
    body = body.replace("MREC", M_REC).replace("MOUT", M_OUT)
    body = body.replace("MERR", M_ERR).replace("MVAL", M_VAL).replace("MEND", M_END)
    entries_lit = "(define entries (list\n  " + "\n  ".join(lit(e.expr) for e in entries) + "))\n"
    return body.replace(";;;ENTRIES;;;", entries_lit)


def run_chibi(entries):
    driver = build_driver(entries)
    fd, path = tempfile.mkstemp(suffix=".scm")
    os.close(fd)
    with open(path, "w", encoding="utf-8") as f:
        f.write(driver)
    env = os.environ.copy()
    env["CHIBI_IGNORE_SYSTEM_PATH"] = "1"
    env["CHIBI_MODULE_PATH"] = CHIBI_LIB
    try:
        p = subprocess.run([CHIBI_EXE, path], env=env, cwd=CHIBI_DIR,
                           capture_output=True, text=True, timeout=60)
        return p.stdout
    except subprocess.TimeoutExpired:
        return None   # a file hung (e.g. circular-structure write) -- skip it
    finally:
        os.remove(path)


def parse_records(out):
    """Return list of (out, kind, payload) where kind is 'val' or 'err'."""
    recs = []
    chunks = out.split(M_REC)
    for ch in chunks[1:]:
        # ch = <MOUT>\n<output>\n<MVAL|MERR>\n<payload>\nMEND...
        if M_OUT not in ch or M_END not in ch:
            recs.append(("", "err", "<driver-protocol-error>"))
            continue
        body = ch.split(M_OUT, 1)[1]
        body = body.split(M_END, 1)[0]
        if M_VAL in body:
            o, payload = body.split(M_VAL, 1)
            kind = "val"
        elif M_ERR in body:
            o, payload = body.split(M_ERR, 1)
            kind = "err"
        else:
            o, payload, kind = body, "", "err"
        recs.append((o.strip("\n"), kind, payload.strip()))
    return recs


# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------
def norm(s):
    return (s or "").strip()


def classify(entry, rec):
    """Return (verdict, note).  verdict in {AGREE, DISAGREE, SKIP}."""
    cout, kind, payload = rec
    # %optional-error% : unspecified behavior -- only termination asserted.
    if entry.exp_err is not None and entry.exp_err.startswith("%optional-error%"):
        return ("SKIP", "optional-error (unspecified)")
    # 'an error is signaled' required (%%% * / %any-error% / exact message)
    if entry.exp_err is not None:
        if kind == "err":
            return ("AGREE", "both error")
        return ("DISAGREE", "suite expects an ERROR; chibi returned value [%s]" % norm(payload))
    # suite expects a specific return value
    if entry.exp_ret is not None:
        if kind == "err":
            return ("DISAGREE", "suite expects [%s]; chibi ERRORED: %s" % (norm(entry.exp_ret), norm(payload)))
        if norm(payload) == norm(entry.exp_ret):
            return ("AGREE", "")
        return ("DISAGREE", "suite expects [%s]; chibi [%s]" % (norm(entry.exp_ret), norm(payload)))
    # no expected retval/error (e.g. a define) -- just shouldn't error
    if kind == "err":
        return ("DISAGREE", "chibi ERRORED where suite expects no error: %s" % norm(payload))
    return ("AGREE", "")


def run_file(path):
    name = os.path.basename(path)
    entries = parse_log(path)
    out = run_chibi(entries)
    if out is None:
        return {"name": name, "n": len(entries), "timed_out": True,
                "agree": 0, "disagree": [], "skip": 0, "results": []}
    recs = parse_records(out)
    results = []
    for e, r in zip(entries, recs):
        results.append((e, r, classify(e, r)))
    for e in entries[len(recs):]:   # entries with no chibi record
        results.append((e, ("", "err", "<no-record>"),
                        ("DISAGREE", "no chibi record (protocol/parse issue)")))
    agree = sum(1 for _, _, (v, _) in results if v == "AGREE")
    disagree = [(e, r, n) for e, r, (v, n) in results if v == "DISAGREE"]
    skip = sum(1 for _, _, (v, _) in results if v == "SKIP")
    return {"name": name, "n": len(entries), "timed_out": False,
            "agree": agree, "disagree": disagree, "skip": skip, "results": results}


def write_run(name, results):
    os.makedirs(RUNS_DIR, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y-%m-%d-%H%M%S")
    out = os.path.join(RUNS_DIR, ts + "-chibidiff-Chibi.run")
    with open(out, "w", encoding="utf-8") as f:
        for e, r, (v, note) in results:
            label = e.expr.split("\n")[0][:60]
            f.write("%-9s %s\n" % (v, label))
            if v == "DISAGREE":
                f.write("         %s\n" % note)
    return out


def main():
    args = sys.argv[1:]
    if args and args[0] == "--suite":
        d = COMPLIANCE_DIR if args[1] == "compliance" else FEATURE_DIR
        files = sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".log"))
    else:
        files = args
    grand_entries = grand_agree = grand_skip = 0
    all_disagree = []
    all_results = []
    for path in files:
        name = os.path.basename(path)
        try:
            r = run_file(path)
        except Exception as ex:
            print("%-48s  ERROR: %s" % (name, ex))
            continue
        all_results.extend(r["results"])
        grand_entries += r["n"]
        grand_agree += r["agree"]
        grand_skip += r["skip"]
        all_disagree.extend((name, e, rec, note) for e, rec, note in r["disagree"])
        if r["timed_out"]:
            flag = "  <-- TIMED OUT (skipped)"
        elif r["disagree"]:
            flag = "  <-- %d DISAGREE" % len(r["disagree"])
        else:
            flag = ""
        print("%-48s %4d entries  %4d agree  %3d skip%s"
              % (name, r["n"], r["agree"], r["skip"], flag))
    print("\nTOTAL: %d entries, %d agree, %d disagree, %d skip"
          % (grand_entries, grand_agree, grand_entries - grand_agree - grand_skip, grand_skip))
    if all_disagree:
        print("\n=== DISAGREEMENTS (chibi vs suite expected) ===")
        for name, e, r, note in all_disagree[:60]:
            print("  [%s] %s" % (name, e.expr.split(chr(10))[0][:70]))
            print("       %s" % note)
    if all_results:
        print("\nrun file:", write_run("all", all_results))


if __name__ == "__main__":
    main()
