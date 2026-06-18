#!/bin/sh
# Alias for backward compatibility -- run-tests.sh (manifest-driven, backlog #9)
# is the orchestrator. With no args it runs the entire arsenal, same as before.
exec sh "$(cd "$(dirname "$0")" && pwd)/run-tests.sh" "$@"
