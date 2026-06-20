#!/usr/bin/env bash
#
# run-via-interp.sh -- launch a Scheme interpreter with the given args.
#
# Usage:  run-via-interp.sh "<interpreter invocation>" <arg>...
#
# The registry's `external` suites substitute {interp} for the running port's
# launch command.  On cppScheme2 that is a single executable path; on pyScheme
# it is the multi-word "python -m pyscheme".  pyScheme's runner spawns the
# (run ...) argv as a LIST, so a multi-word {interp} cannot sit in argv[0] --
# it has to ride as a single ARGUMENT to a shell that re-splits it.  This is the
# same trick cli-tests/run.sh uses: $INTERP is intentionally UNQUOTED so a
# multi-word invocation word-splits into program + flags, while "$@" keeps each
# trailing interpreter argument as one word.  Exits with the interpreter's
# status, so an `(pass exit-0)` suite judges it correctly on both ports.
set -u
INTERP="${1:?usage: run-via-interp.sh \"<interpreter invocation>\" <arg>...}"
shift
exec $INTERP "$@"
