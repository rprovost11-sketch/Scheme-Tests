#!/usr/bin/env python3
"""cross-port-tests/diff.py -- differential macro-expansion harness.

Runs every .scm case in cases/ through BOTH ports -- pyScheme (Python) and
cppScheme2 (C++) -- in file mode and compares their behavior.  The two ports
are MIRROR implementations of the same language, so any behavioral divergence
on identical input is, by construction, a bug in at least one of them.  No
expected values are stored: the oracle is "the other port".  This is part #4b
of the macro-bug-detection effort -- it automates the hand process that caught
3 cppScheme2-only bugs.

WHAT IS COMPARED (and why streams are kept apart):
  * stdout  -- the program's real output (its written values).  Compared
               byte-for-byte: this is where an evaluation divergence shows.
  * exit rc -- compared exactly: catches "one errors, the other doesn't".
  * stderr  -- only its NORMALIZED CORE error message is compared.  The two
               ports legitimately differ in error *chrome* (pyScheme prints
               the file path + a source-line echo + a caret; cppScheme2 prints
               just the message), so the chrome is stripped before comparing.
               A surviving difference means the ports took different error
               paths -- still a real finding, reported as an error-message
               divergence rather than a value divergence.

When --oracle chibi is given, divergent cases are additionally run through
chibi-scheme (the R7RS reference) to suggest WHICH port is wrong.  Chibi runs
the case body on stdin in REPL mode, so its output carries prompt/warning
chrome that this harness only best-effort strips -- treat its verdict as a
hint, not gospel (perfecting it is part #4c).

Usage:
    python diff.py                      # all cases, cross-port diff
    python diff.py cases/swap.scm ...   # only the named case(s)
    python diff.py --oracle chibi       # hint which port is wrong on divergence
    python diff.py --py "<invocation>"  # override the pyScheme invocation
    python diff.py --cpp "<invocation>" # override the cppScheme2 invocation
    python diff.py -v                   # show stdout even for parity cases

Exit status is non-zero if ANY case diverges, so the harness can gate like the
cli-tests do.
"""
import argparse
import glob
import os
import re
import shlex
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CASES_DIR = os.path.join(HERE, "cases")

# scheme-tests/cross-port-tests/diff.py -> .../scheme-tests -> .../Lisp
LISP_ROOT = os.path.dirname(os.path.dirname(HERE))
PY_DIR = os.path.join(LISP_ROOT, "3PyScheme")
CPP_EXE = os.path.join(LISP_ROOT, "4CPPScheme2", "build", "Release", "cppscheme2.exe")

# Chibi reference oracle (mirrors chibi_diff.py's invocation).
CHIBI_DIR = r"D:/SWDEV/tools/chibi-scheme"
CHIBI_EXE = CHIBI_DIR + "/chibi-scheme.exe"
CHIBI_LIB = CHIBI_DIR + "/lib"

# Strips the leading program-name tag ("pyscheme: " / "cppscheme2: ") and, for
# pyScheme, the source location ('"<path>" line N, col C: ') from an error line,
# leaving just the core message so the two ports' errors can be compared.
_PROG_TAG = re.compile(r'^\s*\w+:\s*')
_PY_LOC = re.compile(r'^"[^"]*"\s+line\s+\d+,\s+col\s+\d+:\s*')


class Run:
    """Result of one interpreter run: stdout, normalized stderr core, exit rc."""

    def __init__(self, out, err_core, rc):
        self.out = out
        self.err_core = err_core
        self.rc = rc

    def behaves_like(self, other):
        return (self.out == other.out
                and self.rc == other.rc
                and self.err_core == other.err_core)

    def divergence_kind(self, other):
        """Why this run differs from `other` -- most-serious reason first."""
        if self.out != other.out:
            return "VALUE"          # different written output -- the worst kind
        if self.rc != other.rc:
            return "EXIT"           # one errored, the other did not
        if self.err_core != other.err_core:
            return "ERRMSG"         # both errored, but for different reasons
        return None


def normalize(raw_bytes):
    """CRLF -> LF; strip trailing whitespace per line and overall."""
    text = raw_bytes.decode("utf-8", errors="replace").replace("\r\n", "\n")
    return "\n".join(ln.rstrip() for ln in text.split("\n")).rstrip("\n")


def stderr_core(err_text):
    """Reduce stderr to its core error message, dropping port-specific chrome.

    File-mode errors are a single leading line ('<prog>: [loc] <message>')
    optionally followed (pyScheme only) by a source-line echo and a caret
    line.  We keep only the first line and strip the program tag + location."""
    if not err_text:
        return ""
    first = err_text.split("\n", 1)[0]
    first = _PROG_TAG.sub("", first)
    first = _PY_LOC.sub("", first)
    return first.strip()


def run_file(argv, casefile, cwd=None):
    """Run `argv casefile` in file mode, capturing stdout and stderr apart."""
    try:
        proc = subprocess.run(
            argv + [casefile],
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        return Run(normalize(proc.stdout), stderr_core(normalize(proc.stderr)),
                   proc.returncode)
    except subprocess.TimeoutExpired:
        return Run("<TIMEOUT>", "<TIMEOUT>", -1)


def run_chibi(casefile):
    """Best-effort: feed the case body to chibi on stdin and strip REPL chrome
    (its file compiler mishandles a macro-generated define-syntax with empty
    literals, so stdin is the only reliable path -- see chibi_diff.py)."""
    with open(casefile, "r", encoding="utf-8") as f:
        body = f.read()
    env = dict(os.environ)
    env["CHIBI_IGNORE_SYSTEM_PATH"] = "1"
    env["CHIBI_MODULE_PATH"] = CHIBI_LIB
    try:
        proc = subprocess.run(
            [CHIBI_EXE], input=body.encode("utf-8"),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            cwd=CHIBI_DIR, timeout=30, env=env,
        )
    except FileNotFoundError:
        return None
    except subprocess.TimeoutExpired:
        return Run("<TIMEOUT>", "<TIMEOUT>", -1)
    out = normalize(proc.stdout)
    # REPL chrome: drop "> " prompts and leading WARNING lines from stderr.
    out = out.replace("> ", "").replace(">", "").strip()
    err = "\n".join(ln for ln in normalize(proc.stderr).split("\n")
                    if not ln.startswith("WARNING:"))
    return Run(out, stderr_core(err), proc.returncode)


def main():
    ap = argparse.ArgumentParser(description="cross-port differential macro harness")
    ap.add_argument("cases", nargs="*", help="specific case files (default: all in cases/)")
    ap.add_argument("--py", help="pyScheme invocation (default: python -m pyscheme in 3PyScheme)")
    ap.add_argument("--cpp", help="cppScheme2 invocation (default: the Release exe)")
    ap.add_argument("--oracle", choices=["chibi"], help="hint which port is wrong on divergence")
    ap.add_argument("-v", "--verbose", action="store_true", help="show stdout even for parity cases")
    args = ap.parse_args()

    py_argv = shlex.split(args.py) if args.py else [sys.executable, "-m", "pyscheme"]
    cpp_argv = shlex.split(args.cpp) if args.cpp else [CPP_EXE]
    py_cwd = None if args.py else PY_DIR

    if args.cases:
        case_files = [os.path.abspath(c) for c in args.cases]
    else:
        case_files = sorted(glob.glob(os.path.join(CASES_DIR, "*.scm")))
    if not case_files:
        print("no case files found", file=sys.stderr)
        return 2

    parity = 0
    diverged = []

    print("cross-port differential macro harness")
    print("  pyScheme  : %s  (cwd=%s)" % (" ".join(py_argv), py_cwd or "."))
    print("  cppScheme2: %s" % " ".join(cpp_argv))
    print()

    for cf in case_files:
        name = os.path.basename(cf)
        py = run_file(py_argv, cf, cwd=py_cwd)
        cpp = run_file(cpp_argv, cf)
        if py.behaves_like(cpp):
            parity += 1
            print("  parity   %s" % name)
            if args.verbose:
                _show("py & cpp", py)
        else:
            kind = py.divergence_kind(cpp)
            diverged.append((name, kind))
            print("  DIVERGE  %s  [%s]  (py rc=%d, cpp rc=%d)" % (name, kind, py.rc, cpp.rc))
            _show("pyScheme", py)
            _show("cppScheme2", cpp)
            if args.oracle == "chibi":
                ch = run_chibi(cf)
                if ch is None:
                    print("          (chibi not found at %s)" % CHIBI_EXE)
                else:
                    _show("chibi", ch)
                    print("          --> chibi agrees with: %s" % _adjudicate(py, cpp, ch))

    print()
    print("cross-port: %d parity, %d diverged  (of %d cases)"
          % (parity, len(diverged), len(case_files)))
    for name, kind in diverged:
        print("    %-8s %s" % (kind, name))
    return 1 if diverged else 0


def _show(label, r):
    print("          [%s rc=%d]" % (label, r.rc))
    body = r.out if r.out else "<no stdout>"
    for ln in body.split("\n"):
        print("            out| " + ln)
    if r.err_core:
        print("            err| " + r.err_core)


def _adjudicate(py, cpp, ch):
    py_ok = py.behaves_like(ch)
    cpp_ok = cpp.behaves_like(ch)
    if py_ok and not cpp_ok:
        return "pyScheme  (cppScheme2 is wrong)"
    if cpp_ok and not py_ok:
        return "cppScheme2  (pyScheme is wrong)"
    if py_ok and cpp_ok:
        return "both (?!  re-check normalization)"
    return "NEITHER  (both ports differ from chibi -- shared bug, or chibi chrome)"


if __name__ == "__main__":
    sys.exit(main())
