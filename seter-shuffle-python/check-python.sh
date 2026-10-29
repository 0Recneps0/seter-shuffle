#!/bin/bash
# check-python.sh (SeTeR Shuffle, Python experimental core)
#
# Verifies a REAL python3 exists before anything else runs, and fails
# loudly otherwise. macOS ships a python3 stub that just prompts to
# install developer tools; silently running under that stub would break
# the daily run in a confusing way, so this check exists.
#
# A custom interpreter can be forced with SETER_PYTHON, e.g.:
#   SETER_PYTHON=/opt/homebrew/bin/python3 ./run.sh flowPreview
#
# Exit codes: 0 = usable python3 found (its path is printed);
#             2 = no usable python3, with a fix printed to stderr.
set -u

if [ -n "${SETER_PYTHON:-}" ]; then
  PY="$SETER_PYTHON"
elif command -v python3 >/dev/null 2>&1; then
  PY="$(command -v python3)"
else
  PY=""
fi

if [ -z "$PY" ]; then
  echo "ERROR: no python3 found." >&2
  echo "Install Python 3.9 or newer (from python.org, Homebrew, or Xcode Command Line Tools with: xcode-select --install), then re-run." >&2
  exit 2
fi

# The macOS stub either fails here or prints no usable version. A real
# interpreter prints a version and passes the 3.9+ check below.
VERSION="$("$PY" --version 2>&1)" || {
  echo "ERROR: '$PY' did not run as a real Python interpreter." >&2
  echo "If this Mac only has the macOS python3 stub, install real Python first: xcode-select --install, or python.org / Homebrew, then re-run." >&2
  exit 2
}
if ! "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then
  echo "ERROR: $PY reports '$VERSION', but SeTeR Shuffle (Python) needs Python 3.9 or newer." >&2
  echo "Install a newer Python (python.org or Homebrew) or set SETER_PYTHON to a newer interpreter, then re-run." >&2
  exit 2
fi

echo "$PY ($VERSION)"
exit 0
