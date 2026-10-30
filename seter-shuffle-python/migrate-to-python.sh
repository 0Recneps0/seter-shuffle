#!/bin/bash
# migrate-to-python.sh (SeTeR Shuffle, Python build, proposed stable v3.0)
#
# Migration from the v2.6 AppleScript daily run to the Python daily
# run, and rollback the other way. This script is the ONLY place
# the v2.6 launchd job is ever disabled, and it does so ONLY when
# run explicitly with --confirm. By default (no flag, or --dry-run)
# it prints the exact plan and changes NOTHING.
#
# What --confirm does, in order:
#   1. Verifies the Python install exists (setup-python.sh output)
#      and its daily plist exists; if either is missing, it stops
#      and changes nothing.
#   2. Verifies the Rediscover history file is readable if it
#      exists (~/Documents/SeTeRShuffle/rediscover-history.tsv);
#      a missing history file is NOT an error (the first Python
#      Rediscover apply creates it), but it is reported.
#   3. Unloads the v2.6 launchd job (com.seter.daily) and renames
#      its plist to com.seter.daily.plist.disabled-<timestamp>,
#      in the same directory. The v2.6 script, its backups, its
#      history, and its apps are NEVER deleted, moved, or edited.
#   4. Loads the Python daily plist (com.seter.python.daily),
#      if setup-python.sh already wrote it.
#   5. Writes a migration record (migration-<timestamp>.txt) next
#      to the disabled v2.6 plist, naming both plist paths, so
#      rollback can find them without guessing.
#
# Rollback (--rollback):
#   1. Unloads the Python daily job (com.seter.python.daily).
#   2. Restores the newest disabled v2.6 plist to its original
#      name and loads it.
#   3. Leaves the Python install directory in place, so a second
#      migration does not need a reinstall; re-running setup and
#      then --confirm switches back.
#   Rollback NEVER deletes the Python install, its backups, its
#   logs, or Rediscover history.
#
# Usage:
#   bash migrate-to-python.sh [--dry-run] [--confirm] [--rollback] [-h|--help]
#
# Test hooks (unit tests only):
#   SETER_TEST_MODE=1        skip macOS-only checks and launchctl
#                            calls (file renames still happen, in
#                            the override directories below)
#   SETER_LAUNCHAGENTS_DIR   override the LaunchAgents directory
#   SETER_PYTHON_INSTALL_DIR override the Python install directory
#   SETER_V26_DIR            override the v2.6 install directory
#                            (checked for existence only, never written)

set -euo pipefail

OLD_LABEL="com.seter.daily"
NEW_LABEL="com.seter.python.daily"
PLIST_DIR="${SETER_LAUNCHAGENTS_DIR:-$HOME/Library/LaunchAgents}"
OLD_PLIST="$PLIST_DIR/$OLD_LABEL.plist"
NEW_PLIST="$PLIST_DIR/$NEW_LABEL.plist"
PYTHON_INSTALL_DIR="${SETER_PYTHON_INSTALL_DIR:-$HOME/Documents/SeTeRShufflePython}"
V26_DIR="${SETER_V26_DIR:-$HOME/Documents/SeTeRShuffle}"
HISTORY="$HOME/Documents/SeTeRShuffle/rediscover-history.tsv"

MODE="dry-run"

usage() {
  cat <<'EOF'
SeTeR Shuffle migration: v2.6 AppleScript daily -> Python daily (proposed v3.0)

Usage: bash migrate-to-python.sh [mode]

  --dry-run   (default) print the exact plan and change nothing
  --confirm   actually disable the v2.6 daily job and enable the Python one
  --rollback  disable the Python daily job and restore the v2.6 one
  -h, --help  show this help

Nothing is deleted by any mode: the v2.6 script, backups, history,
and apps stay in place, and the Python install stays in place on
rollback. Only launchd job state and plist filenames change.
EOF
}

say() { printf '%s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --confirm) MODE="confirm"; shift ;;
    --rollback) MODE="rollback"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Error: Unknown option: %s (try --help)\n' "$1" >&2; exit 1 ;;
  esac
done

launchd_unload_label() {
  local plist="$1"
  if [ -n "${SETER_TEST_MODE:-}" ]; then return 0; fi
  local uid
  uid="$(id -u)"
  launchctl bootout "gui/$uid" "$plist" >/dev/null 2>&1 || launchctl unload "$plist" >/dev/null 2>&1 || true
}

launchd_load_label() {
  local plist="$1"
  if [ -n "${SETER_TEST_MODE:-}" ]; then return 0; fi
  local uid
  uid="$(id -u)"
  if launchctl bootstrap "gui/$uid" "$plist" >/dev/null 2>&1; then return 0; fi
  launchctl load "$plist"
}

plan() {
  say "Migration plan (v2.6 -> Python daily, proposed v3.0):"
  say "  1. Verify Python install exists: $PYTHON_INSTALL_DIR"
  say "  2. Verify Python daily plist exists: $NEW_PLIST"
  say "  3. Check Rediscover history (read-only, never moved): $HISTORY"
  say "  4. Unload v2.6 job $OLD_LABEL and rename its plist to $OLD_LABEL.plist.disabled-<timestamp>"
  say "  5. Load Python daily job $NEW_LABEL"
  say "  Never deleted or edited: v2.6 script, v2.6 backups, v2.6 apps, Rediscover history, any playlist."
  say "  Rollback: bash migrate-to-python.sh --rollback"
}

if [ "$MODE" = "dry-run" ]; then
  plan
  say "Dry run: nothing was changed. Re-run with --confirm to apply this plan."
  exit 0
fi

if [ -z "${SETER_TEST_MODE:-}" ]; then
  [ "$(uname -s)" = "Darwin" ] || { printf 'Error: migration only runs on macOS.\n' >&2; exit 1; }
fi

if [ "$MODE" = "rollback" ]; then
  say "Rolling back: Python daily -> v2.6 daily"
  launchd_unload_label "$NEW_PLIST"
  say "  unloaded Python daily job $NEW_LABEL"
  DISABLED="$(ls -t "$PLIST_DIR/$OLD_LABEL.plist.disabled-"* 2>/dev/null | head -n 1 || true)"
  if [ -z "$DISABLED" ]; then
    printf 'Error: no disabled v2.6 plist found in %s; nothing was restored.\n' "$PLIST_DIR" >&2
    exit 1
  fi
  mv "$DISABLED" "$OLD_PLIST"
  say "  restored v2.6 plist from $(basename "$DISABLED")"
  launchd_load_label "$OLD_PLIST"
  say "  loaded v2.6 daily job $OLD_LABEL"
  say "Rollback done. Python install left in place at $PYTHON_INSTALL_DIR."
  exit 0
fi

# --confirm
plan
say ""
[ -d "$PYTHON_INSTALL_DIR" ] || { printf 'Error: Python install not found at %s; run setup-python.sh first. Nothing was changed.\n' "$PYTHON_INSTALL_DIR" >&2; exit 1; }
[ -f "$NEW_PLIST" ] || { printf 'Error: Python daily plist not found at %s; run setup-python.sh (without --no-daily) first. Nothing was changed.\n' "$NEW_PLIST" >&2; exit 1; }
if [ -f "$HISTORY" ]; then
  say "  Rediscover history found (carried over as-is): $HISTORY"
else
  say "  NOTE: no Rediscover history file yet at $HISTORY; the first Python Rediscover apply will create it."
fi
if [ ! -d "$V26_DIR" ]; then
  say "  NOTE: v2.6 install directory not found at $V26_DIR; continuing with the launchd job only."
fi
if [ ! -f "$OLD_PLIST" ]; then
  say "  NOTE: no v2.6 daily plist at $OLD_PLIST; nothing to disable. Loading the Python job only."
else
  launchd_unload_label "$OLD_PLIST"
  STAMP="$(date +%Y%m%d-%H%M%S)"
  mv "$OLD_PLIST" "$PLIST_DIR/$OLD_LABEL.plist.disabled-$STAMP"
  say "  disabled v2.6 job $OLD_LABEL; plist renamed to $OLD_LABEL.plist.disabled-$STAMP"
  {
    printf 'SeTeR Shuffle migration %s\n' "$STAMP"
    printf 'disabled v2.6 plist: %s\n' "$PLIST_DIR/$OLD_LABEL.plist.disabled-$STAMP"
    printf 'python daily plist: %s\n' "$NEW_PLIST"
    printf 'python install: %s\n' "$PYTHON_INSTALL_DIR"
    printf 'rollback: bash migrate-to-python.sh --rollback\n'
  } > "$PLIST_DIR/migration-$STAMP.txt"
fi
launchd_load_label "$NEW_PLIST"
say "  loaded Python daily job $NEW_LABEL"
say "Migration done. v2.6 script, backups, history, and apps were left untouched."
