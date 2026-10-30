#!/bin/bash
# install-or-update.sh (SeTeR Shuffle v3.0.6, one-click install or update)
#
# Bash 3.2 note (macOS ships bash 3.2): this script contains NO
# array expansions at all. The v3.0 build died on a default run
# with "SETUP_ARGS[@]: unbound variable" because expanding an
# empty array under set -u is an error on bash 3.2, unlike bash 5
# on Linux. Setup arguments are rebuilt with set -- / "$@" here,
# which is safe when empty even on bash 3.2, and the v3.0.2
# regression test pins that default path.
#
# Execute-bit note: release zips have shipped these scripts with
# the execute bit stripped (mode 660), so double-clicking the
# .command wrapper gave "permission denied". This script chmods
# +x its own helpers at the start of every run (setup-python.sh,
# check-python.sh, daily.sh, run.sh, migrate-to-python.sh,
# install-or-update.sh, SeTeR-Shuffle-Install.command), before
# invoking any of them, so a future zip with stripped modes
# still works. Running via `bash install-or-update.sh` never
# needed the bit in the first place.
#
# One confirmation, then everything in order:
#   1. Verify a real python3 (3.9+) exists.
#   2. Install or update ~/Documents/SeTeRShufflePython to v3.0.6
#      (differing files get a timestamped .bak first; backups, logs,
#      and Rediscover history are never deleted).
#   3. Write and load the 8:00 AM com.seter.python.daily plist.
#   4. Run migrate-to-python.sh --dry-run, then --confirm, but
#      ONLY if the v2.6 daily job (com.seter.daily) is still
#      enabled. If it is already disabled, migration is skipped.
#   5. Verify the final state: install dir present, Python plist
#      present, v2.6 plist gone (or disabled).
#
# What it NEVER does:
#   - Never deletes or edits the v2.6 script, its backups, its
#     apps, or Rediscover history. Migration only renames the
#     v2.6 plist to .disabled-<timestamp>; rollback restores it.
#   - Never auto-probes. The 8am daily run still refuses without
#     a fresh (<48h) per-target mapping for the main playlist and
#     for "SeTeR Rediscover" (see the reminder printed at the end).
#   - Never touches a playlist in Music itself.
#
# On any failure it stops immediately, prints exactly what
# failed, and leaves rollback available:
#   bash ~/Documents/SeTeRShufflePython/migrate-to-python.sh --rollback
#
# Usage:
#   bash install-or-update.sh [--yes] [--playlist NAME]
#                              [--hour H] [--minute M] [--force]
#   --yes          answer the one confirmation prompt automatically
#   --playlist     daily playlist (default: My New Sandwich Recipe)
#   --hour/--minute daily time (default 8:00, matching v2.6)
#   --force        pass --force through to setup-python.sh
#                  (needed when updating from a 3.0-proposed install)
#
# Test hooks (unit tests only, never used by a real install):
#   SETER_TEST_MODE=1        skip macOS-only checks and python check
#   SETER_PYTHON_INSTALL_DIR override the Python install directory
#   SETER_LAUNCHAGENTS_DIR   override the LaunchAgents directory
#   SETER_STATE_DIR          override the log/state directory
#
# This script is also shipped at the repository root as
# install-or-update.sh, for git-clone users; the copy inside
# seter-shuffle-python/ is the one in the release zip.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
# When run from the repository root copy, the Python tree lives
# in seter-shuffle-python/ next to this script.
if [ ! -f "$SCRIPT_DIR/setup-python.sh" ] && [ -f "$SCRIPT_DIR/seter-shuffle-python/setup-python.sh" ]; then
  SCRIPT_DIR="$SCRIPT_DIR/seter-shuffle-python"
fi

# Restore the execute bit on our own helpers before invoking any
# of them. Release zips have stripped modes before (660), which
# made double-clicking the .command wrapper fail with
# "permission denied". Mode changes only; no content is touched,
# and this runs even if the user later declines the prompt.
for helper in setup-python.sh check-python.sh daily.sh run.sh migrate-to-python.sh install-or-update.sh SeTeR-Shuffle-Install.command; do
  if [ -f "$SCRIPT_DIR/$helper" ]; then
    chmod +x "$SCRIPT_DIR/$helper" 2>/dev/null || true
  fi
done

ASSUME_YES=0
FORCE=0 # shellcheck disable=SC2034
PLAYLIST=""
HOUR=""
MINUTE=""

usage() {
  cat <<'EOF'
SeTeR Shuffle v3.0.6 -- one-click install or update

Usage: bash install-or-update.sh [--yes] [--playlist NAME] [--hour H] [--minute M] [--force]

With one "yes" it installs or updates the Python build, schedules
the 8:00 AM daily run, and switches the daily job from v2.6 to
Python (migration), unless v2.6 is already disabled. Backups,
logs, and Rediscover history are kept; the v2.6 script and
backups are never deleted or edited. Rollback, if ever needed:
  bash ~/Documents/SeTeRShufflePython/migrate-to-python.sh --rollback
EOF
}

say() { printf '%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1; shift ;;
    --force) FORCE=1; shift ;; # accepted; --force is always passed to setup below
    --playlist) [ $# -ge 2 ] || die "--playlist needs a playlist name"; PLAYLIST="$2"; shift 2 ;;
    --playlist=*) PLAYLIST="${1#*=}"; shift ;;
    --hour) [ $# -ge 2 ] || die "--hour needs a number from 0 to 23"; HOUR="$2"; shift 2 ;;
    --hour=*) HOUR="${1#*=}"; shift ;;
    --minute) [ $# -ge 2 ] || die "--minute needs a number from 0 to 59"; MINUTE="$2"; shift 2 ;;
    --minute=*) MINUTE="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

if [ -z "${SETER_TEST_MODE:-}" ]; then
  [ "$(uname -s)" = "Darwin" ] || die "SeTeR Shuffle drives the Music app, so it only runs on macOS."
  for tool in osascript launchctl; do
    command -v "$tool" >/dev/null 2>&1 || die "Missing '$tool', which ships with macOS."
  done
fi

INSTALL_DIR="${SETER_PYTHON_INSTALL_DIR:-$HOME/Documents/SeTeRShufflePython}"
PLIST_DIR="${SETER_LAUNCHAGENTS_DIR:-$HOME/Library/LaunchAgents}"
OLD_PLIST="$PLIST_DIR/com.seter.daily.plist"
NEW_PLIST="$PLIST_DIR/com.seter.python.daily.plist"
MARKER_FILE="$INSTALL_DIR/installed-version.txt"

say "SeTeR Shuffle v3.0.6 -- one-click install or update"
say ""
if [ -f "$MARKER_FILE" ]; then
  say "Existing install found at $INSTALL_DIR (version: $(cat "$MARKER_FILE" 2>/dev/null || echo unknown)). This will update it in place."
else
  say "No existing Python install found. This will install fresh into $INSTALL_DIR."
fi
say "It will then schedule the 8:00 AM daily run and, if the v2.6"
say "daily job is still enabled, switch it off (migration)."
say "Your v2.6 script, backups, and Rediscover history are kept."
say ""

if [ "$ASSUME_YES" != 1 ]; then
  printf 'Proceed? Type yes to continue, anything else to stop: '
  read -r answer || die "No answer given; nothing was changed."
  case "$answer" in
    y|yes|Y|YES) ;;
    *) say "Stopped by you. Nothing was changed."; exit 0 ;;
  esac
fi

# 1. Real python3, before anything is installed or changed.
if [ -z "${SETER_TEST_MODE:-}" ]; then
  bash "$SCRIPT_DIR/check-python.sh" >/dev/null || die "No usable python3 (3.9+) found; install real Python first, then re-run. Nothing was changed."
  say "ok python3 check passed"
else
  say "ok python3 check skipped (test mode)"
fi

# 2. Install or update, with the 8am schedule. --force is always
# passed through here (the user already confirmed once in this
# script), so an update from a 3.0-proposed or 3.0 install is
# allowed; setup-python.sh still .bak's every differing file
# first. Arguments are rebuilt with set -- / "$@" on purpose:
# NO array is used anywhere in this script, because expanding an
# empty array under set -u is an unbound-variable error on
# macOS bash 3.2, which is exactly how the v3.0 default run died
# at Step 1 before any migration. "$@" with no arguments expands
# to nothing safely even on bash 3.2.
set --
[ -n "$PLAYLIST" ] && set -- "$@" --playlist "$PLAYLIST"
[ -n "$HOUR" ] && set -- "$@" --hour "$HOUR"
[ -n "$MINUTE" ] && set -- "$@" --minute "$MINUTE"
set -- "$@" --force
say "Step 1 of 3: installing/updating into $INSTALL_DIR ..."
bash "$SCRIPT_DIR/setup-python.sh" "$@" || die "setup-python.sh failed; nothing was migrated. Your previous install (if any) and v2.6 job are untouched except for any .bak files setup kept. Re-run this script after fixing the error above."
say "ok install/update done"

# 3a. Verify the install and the schedule before migrating.
[ -d "$INSTALL_DIR" ] || die "Install directory $INSTALL_DIR is missing after setup; stopping before migration. Rollback (if a migration already happened earlier): bash $INSTALL_DIR/migrate-to-python.sh --rollback"
[ -f "$NEW_PLIST" ] || die "Python daily plist $NEW_PLIST is missing after setup; stopping before migration. Run setup-python.sh (without --no-daily) first, then re-run this script."
say "ok install and 8am schedule verified"

# 3b. Migrate only if the v2.6 job is still enabled.
if [ -f "$OLD_PLIST" ]; then
  say "Step 2 of 3: migration dry run (changes nothing) ..."
  bash "$INSTALL_DIR/migrate-to-python.sh" --dry-run || die "Migration dry run failed; stopping before any change to v2.6. Nothing was migrated."
  say "Step 3 of 3: migrating (disabling v2.6 daily, enabling Python daily) ..."
  bash "$INSTALL_DIR/migrate-to-python.sh" --confirm || die "Migration --confirm failed; check the error above. Rollback is available: bash $INSTALL_DIR/migrate-to-python.sh --rollback"
  say "ok migration done"
else
  say "Step 2 of 3: no v2.6 daily plist found; migration already done or never present. Skipping migration."
  say "Step 3 of 3: nothing to migrate."
fi

# 4. Final verification.
[ -d "$INSTALL_DIR" ] || die "Final check failed: install directory missing."
[ -f "$NEW_PLIST" ] || die "Final check failed: Python daily plist missing."
if [ -f "$OLD_PLIST" ]; then
  die "Final check failed: v2.6 daily plist is still present; migration did not take effect. Rollback is available: bash $INSTALL_DIR/migrate-to-python.sh --rollback"
fi
say ""
say "Done. SeTeR Shuffle v3.0.6 is installed and scheduled for 8:00 AM."
say "  Install: $INSTALL_DIR"
say "  Daily job: com.seter.python.daily (8:00 AM)"
say "  v2.6 daily job: disabled (script and backups kept; rollback: bash $INSTALL_DIR/migrate-to-python.sh --rollback)"
say ""
say "NOTE: the daily run self-probes \"the daily playlist\" and \"SeTeR Rediscover\""
say "itself each morning (since v3.0.2) and refuses to change anything if"
say "a fresh per-target mapping can't be measured. To check it now:"
say "  cd $INSTALL_DIR && ./run.sh audit"
