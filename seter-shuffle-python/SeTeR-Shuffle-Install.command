#!/bin/bash
# Double-click this file in Finder to install or update SeTeR Shuffle v3.0.4.
# It runs install-or-update.sh from this same folder, then waits so you
# can read the result before the Terminal window closes.
cd "$(dirname "$0")" || exit 1
bash ./install-or-update.sh
echo ""
read -r -p "Done. Press Return to close this window. " _ || true
