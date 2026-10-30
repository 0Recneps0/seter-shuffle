#!/bin/bash
# daily.sh (SeTeR Shuffle, Python build, proposed stable v3.0)
#
# The daily run, matching stable v2.6's daily behavior as closely as
# the Python build allows:
#   1. Save a once-a-day library manifest (ID, artist, album, title),
#      kept 14 days, under the install directory's backups/.
#   2. Dedupe the daily playlist (no-op when it is already clean),
#      then shuffle it in place (v2.6 dailyRemoveDuplicates = true).
#   3. Refresh "SeTeR Rediscover" and record history only after a
#      successful apply (run.sh does that part).
#
# Usage (called by launchd, or by hand):
#   ./daily.sh "My New Sandwich Recipe"
#   ./daily.sh                      # default playlist, same name
#
# HARD RULES (do not weaken these for convenience):
# - This script NEVER probes. A daily run needs a fresh (<48h)
#   per-target mapping for EACH target it touches (the daily
#   playlist AND "SeTeR Rediscover"), recorded by a manual
#   ./run.sh sortprobe on a throwaway set to that target's sort.
#   If either mapping is missing, stale, or for another target,
#   the run stops BEFORE touching Music and says exactly which
#   sortprobe to run. It never falls back to another target's
#   mapping, and it never auto-probes: an automated probe would
#   measure a throwaway whose sort nobody just verified, which is
#   exactly how the 2026-10-29 mapping-transfer failure happened.
#   Practical consequence, stated plainly: an evening sortprobe
#   now covers the next TWO mornings' 8am runs (48h window), but
#   a run still fails closed on any morning without a probe in
#   the previous 48 hours. Verify-after still fails closed if
#   the sort actually changed in the window, so a stale mapping
#   costs a refused run, never a corrupted playlist.
# - This script NEVER touches the v2.6 install
#   (~/Documents/SeTeRShuffle) or its launchd job (com.seter.daily).
#   Migration disables that job only when migrate-to-python.sh is
#   run explicitly with --confirm; this script does not do it.
# - State, logs, and Rediscover history paths are the same ones
#   run.sh uses, so the daily run and manual runs share backups
#   and history instead of forking them.
#
# Test hooks (used by the unit tests only, never by launchd):
#   SETER_STATE_DIR       override the state directory
#   SETER_DAILY_DRY_RUN=1 pass the mapping pre-check, print the
#                         planned steps, and exit 0 without
#                         calling run.sh or Music at all.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PLAYLIST="${1:-My New Sandwich Recipe}"
STATE="${SETER_STATE_DIR:-$HOME/Library/Logs/seter-shuffle-python}"
LOG="$STATE/daily.log"
BACKUP_DIR="${SETER_BACKUP_DIR:-$ROOT/backups}"
HISTORY="$HOME/Documents/SeTeRShuffle/rediscover-history.tsv"
REDISCOVER_PLAYLIST="SeTeR Rediscover"

mkdir -p "$STATE" "$BACKUP_DIR" 2>/dev/null || true

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

# Best-effort macOS notification (same rule as run.sh notify):
# never blocks or fails the run if Notification Center or
# osascript is unavailable.
notify() {
  local msg
  msg="$(printf '%s' "$*" | tr -d '"')"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$msg\" with title \"SeTeR Shuffle\"" >/dev/null 2>&1 || log "notification unavailable: $msg"
  else
    log "notification unavailable (no osascript): $msg"
  fi
}

die() { log "DAILY FAILED: $*"; notify "SeTeR Shuffle daily run failed: $*"; exit 1; }

# Mapping filename for one target: sanitized name plus a hash of the
# full name, exactly the scheme run.sh mapping_file_for uses, so
# this pre-check reads the same file run.sh will read.
mapping_file_for() {
  local name="$1" safe hash
  safe="$(printf '%s' "$name" | tr '\n\r' '__' | tr ' /' '__')"
  if command -v shasum >/dev/null 2>&1; then
    hash="$(printf '%s' "$name" | shasum -a 256 | cut -c1-12)"
  elif command -v md5 >/dev/null 2>&1; then
    hash="$(printf '%s' "$name" | md5 | cut -c1-12)"
  else
    hash="nohash"
  fi
  printf '%s/sort-mapping-%s-%s.txt' "$STATE" "$safe" "$hash"
}

# Refuse unless TARGET has a fresh, correctly-targeted mapping.
# Prints the exact manual sortprobe command on failure.
check_mapping() {
  local target="$1" map_file mapping recorded_target sort_label ts now
  map_file="$(mapping_file_for "$target")"
  if [ ! -f "$map_file" ]; then
    log "DAILY FAILED: no per-target sort mapping recorded for '$target'."
    log "Run this by hand first (throwaway set to '$target' sort in Music):"
    log "  ./run.sh sortprobe <throwaway> '$target' '<sort-label>'"
    return 1
  fi
  mapping="$(grep '^MAPPING: ' "$map_file" | head -n 1 | sed 's/^MAPPING: //')"
  recorded_target="$(grep '^TARGET: ' "$map_file" | head -n 1 | sed 's/^TARGET: //')"
  sort_label="$(grep '^SORT: ' "$map_file" | head -n 1 | sed 's/^SORT: //')"
  ts="$(grep '^TIMESTAMP: ' "$map_file" | head -n 1 | sed 's/^TIMESTAMP: //')"
  now="$(date +%s)"
  if [ "$mapping" != "forward" ] && [ "$mapping" != "reversed" ]; then
    log "DAILY FAILED: recorded mapping for '$target' is not forward or reversed (got '$mapping'); re-run sortprobe."
    return 1
  fi
  if [ "$recorded_target" != "$target" ]; then
    log "DAILY FAILED: mapping file for '$target' names target '$recorded_target'; mappings do not transfer between targets; re-run sortprobe for '$target'."
    return 1
  fi
  if [ -z "$sort_label" ]; then
    log "DAILY FAILED: recorded mapping for '$target' has no sort label; re-run sortprobe with a sort label."
    return 1
  fi
  case "$ts" in
    ''|*[!0-9]*)
      log "DAILY FAILED: recorded mapping for '$target' has no valid timestamp; re-run sortprobe."
      return 1
      ;;
  esac
  if [ $((now - ts)) -gt 172800 ]; then
    log "DAILY FAILED: recorded mapping for '$target' is older than 48 hours; re-run sortprobe so the mapping matches the target's current sort."
    return 1
  fi
  log "daily mapping OK for '$target': $mapping (sort '$sort_label')"
  return 0
}

log "daily run starting for playlist '$PLAYLIST'"

# Python check first, before Music is touched (same rule as run.sh).
if [ -z "${SETER_DAILY_DRY_RUN:-}" ]; then
  CHECK_OUT="$(bash "$ROOT/check-python.sh")" || die "no usable python3: $CHECK_OUT"
  log "python: $CHECK_OUT"
fi

check_mapping "$PLAYLIST" || exit 1
check_mapping "$REDISCOVER_PLAYLIST" || exit 1

if [ -n "${SETER_DAILY_DRY_RUN:-}" ]; then
  log "dry run: mappings OK; planned steps: library manifest, dedupe '$PLAYLIST', shuffle '$PLAYLIST', rediscover"
  log "daily dry run done; nothing was changed"
  exit 0
fi

# 1. Library manifest (once a day, kept 14 days). A manifest for
# today that already exists is left alone; the dump itself still
# goes through the bridge, so a failed dump fails the run here,
# before any playlist is touched.
TODAY="$(date +%Y-%m-%d)"
MANIFEST="$BACKUP_DIR/library-manifest-$TODAY.tsv"
if [ ! -f "$MANIFEST" ]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  if ! osascript "$ROOT/bridge/dump-library.applescript" "$WORK/library.json" 2>&1 | tee -a "$LOG"; then
    die "library dump for the daily manifest failed"
  fi
  PY="$(bash "$ROOT/check-python.sh" | cut -d' ' -f1)"
  PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}" "$PY" -m seter_shuffle.cli library-manifest --library "$WORK/library.json" --out "$MANIFEST" >> "$LOG" 2>&1 \
    || die "library manifest write failed"
  log "daily manifest written: $MANIFEST"
  find "$BACKUP_DIR" -name 'library-manifest-*.tsv' -mtime +14 -delete 2>/dev/null || true
else
  log "daily manifest already exists for today: $MANIFEST"
fi

# 2-3. Dedupe, then shuffle, then Rediscover. Each step goes
# through run.sh's own gates (fresh mapping, validate, snapshot,
# verify, restore on failure). Any failure stops the run here:
# a failed shuffle must not be followed by a Rediscover refresh
# that would burn cooldown on a half-done day.
"$ROOT/run.sh" dedupe "$PLAYLIST" >> "$LOG" 2>&1 || die "dedupe '$PLAYLIST' failed (see $LOG)"
log "daily dedupe done for '$PLAYLIST'"
"$ROOT/run.sh" shuffle "$PLAYLIST" >> "$LOG" 2>&1 || die "shuffle '$PLAYLIST' failed (see $LOG)"
log "daily shuffle done for '$PLAYLIST'"
"$ROOT/run.sh" rediscover >> "$LOG" 2>&1 || die "rediscover failed (see $LOG)"
log "daily rediscover done"

log "daily run done for '$PLAYLIST'"
notify "SeTeR Shuffle daily run done for $PLAYLIST"
exit 0
