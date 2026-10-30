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
# - This script AUTO SELF-PROBES (v3.0.2). Before the mapping
#   check, it runs ./run.sh selfprobe on EACH target it touches
#   (the daily playlist AND "SeTeR Rediscover"), refreshing that
#   target's per-target mapping from the target itself, under
#   the target's own sort, which Music remembers per playlist.
#   That is why an automated probe is safe here when it was not
#   before: the old ban was on auto-probing a THROWAWAY, whose
#   sort nobody just verified, which is exactly how the
#   2026-10-29 mapping-transfer failure happened (a mapping
#   measured on one playlist's sort used for another's). A
#   self-probe cannot transfer: the mapping it measures is the
#   target's own, by construction. The 48-hour manual-probe
#   chore is gone, but the mapping gate is NOT dropped: after
#   the self-probes, the run still refuses unless each target
#   has a fresh, correctly-targeted, forward/reversed mapping,
#   and verify-after still fails closed if a sort changed
#   mid-run, so a stale mapping costs a refused run, never a
#   corrupted playlist. It never falls back to another target's
#   mapping, and it never uses a fresh throwaway probe.
# - If a self-probe fails for either target, the daily run
#   fails closed BEFORE any build, dedupe, or Rediscover step,
#   and BEFORE probing the other target (the two probes share
#   one snapshot file, $STATE/sort-probe-snapshot.txt, so a
#   second probe would overwrite the snapshot needed to
#   restore the first target). The failure log names the
#   target and the snapshot path, and the restore command.
#   A self-probe snapshots the target first, builds a
#   rotation, restores the snapshot under the measured mapping,
#   and verifies the restore before returning OK; a failed
#   restore leaves the target holding the rotation order, with
#   the snapshot named, recoverable via
#   ./run.sh restore <target> <snapshot>. An "other" mapping
#   is still an abort, never a build.
# - TRIAL-DEDUPE BREAKS THE OLD DEADLOCK (v3.0.4): the
#   duplicate-entry refusal is unchanged, so a self-probe on
#   a playlist with duplicate entries still refuses and
#   changes nothing. But the daily run no longer stops there:
#   when the daily playlist's probe refuses ONLY on duplicate
#   entries (the probe output says so), the daily run attempts
#   ./run.sh dedupe on that playlist, which trial-dedupes
#   (forward, then reversed, verify-after as the oracle) and
#   records the winning mapping. A probe failure for any
#   other reason still stops the run immediately, and a failed
#   trial-dedupe stops it before shuffle/rediscover. The
#   Rediscover probe has no trial fallback: Rediscover is a
#   generated playlist, and a doubled Rediscover is a manual
#   dedupe, not a daily-run repair.
# - Dry runs (SETER_DAILY_DRY_RUN=1, a test hook never used by
#   launchd) do NOT run the self-probes, because a dry run
#   changes nothing; they log the planned probes instead and
#   then run the mapping check on the recorded mappings.
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
#                         calling run.sh or Music at all (the auto
#                         self-probes are logged as planned, not run).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PLAYLIST="${1:-My New Sandwich Recipe}"
STATE="${SETER_STATE_DIR:-$HOME/Library/Logs/seter-shuffle-python}"
LOG="$STATE/daily.log"
BACKUP_DIR="${SETER_BACKUP_DIR:-$ROOT/backups}"
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

# Auto self-probe one target before the mapping check. Return
# codes: 0 on success; 2 when the probe refused ONLY on
# duplicate entries (the caller may then try trial-dedupe, which
# is the one repair that does not need a probe); 1 on any other
# failure, in which case the whole daily run stops here: do not
# probe the other target (shared snapshot file), do not build
# anything. The probe output is captured to a file first so the
# duplicate wording can be checked without guessing from the
# exit code alone: a generic probe failure must never trigger
# a dedupe attempt.
auto_self_probe() {
  local target="$1" snapshot probe_out
  snapshot="$STATE/sort-probe-snapshot.txt"
  probe_out="$STATE/daily-probe.out"
  log "daily auto self-probe for '$target' (probing the target itself under its own sort)"
  if "$ROOT/run.sh" selfprobe "$target" > "$probe_out" 2>&1; then
    cat "$probe_out" >> "$LOG"
    log "daily auto self-probe OK for '$target'"
    return 0
  fi
  cat "$probe_out" >> "$LOG"
  if grep -q "duplicate song entry" "$probe_out"; then
    log "daily auto self-probe for '$target' refused on duplicate entries only; trial-dedupe will be attempted (it verifies its own mapping, it does not probe)"
    return 2
  fi
  log "DAILY FAILED: auto self-probe failed for '$target'; daily stopped before any build, dedupe, or rediscover, and before probing the other target."
  log "DAILY FAILED: if the probe could not restore '$target', it may hold the rotation order; its snapshot is at $snapshot; restore it with ./run.sh restore '$target' '$snapshot', then re-run the daily run (it will self-probe again)."
  return 1
}

# Refuse unless TARGET has a fresh, correctly-targeted mapping.
# Prints the manual self-probe command on failure (the daily run
# already auto self-probed by the time this runs, so reaching
# here means the probe passed but the recorded mapping is still
# not usable, which should not happen; the manual command is
# the fallback, not the normal path).
check_mapping() {
  local target="$1" map_file mapping recorded_target sort_label ts now
  map_file="$(mapping_file_for "$target")"
  if [ ! -f "$map_file" ]; then
    log "DAILY FAILED: no per-target sort mapping recorded for '$target'."
    log "Run this by hand first (probe the target itself under its own sort):"
    log "  ./run.sh selfprobe '$target'"
    return 1
  fi
  mapping="$(grep '^MAPPING: ' "$map_file" | head -n 1 | sed 's/^MAPPING: //')"
  recorded_target="$(grep '^TARGET: ' "$map_file" | head -n 1 | sed 's/^TARGET: //')"
  sort_label="$(grep '^SORT: ' "$map_file" | head -n 1 | sed 's/^SORT: //')"
  ts="$(grep '^TIMESTAMP: ' "$map_file" | head -n 1 | sed 's/^TIMESTAMP: //')"
  now="$(date +%s)"
  if [ "$mapping" != "forward" ] && [ "$mapping" != "reversed" ]; then
    log "DAILY FAILED: recorded mapping for '$target' is not forward or reversed (got '$mapping'); re-run ./run.sh selfprobe '$target'."
    return 1
  fi
  if [ "$recorded_target" != "$target" ]; then
    log "DAILY FAILED: mapping file for '$target' names target '$recorded_target'; mappings do not transfer between targets; re-run ./run.sh selfprobe '$target'."
    return 1
  fi
  if [ -z "$sort_label" ]; then
    log "DAILY FAILED: recorded mapping for '$target' has no sort label; re-run ./run.sh selfprobe '$target'."
    return 1
  fi
  case "$ts" in
    ''|*[!0-9]*)
      log "DAILY FAILED: recorded mapping for '$target' has no valid timestamp; re-run ./run.sh selfprobe '$target'."
      return 1
      ;;
  esac
  if [ $((now - ts)) -gt 172800 ]; then
    log "DAILY FAILED: recorded mapping for '$target' is older than 48 hours; re-run ./run.sh selfprobe '$target'."
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

# Auto self-probe each target, in order, BEFORE the mapping
# check and before any build. A non-duplicate failure in the
# first probe stops the run before the second probe (shared
# snapshot file) and before anything else is touched. A
# duplicate-only failure for the daily playlist triggers
# trial-dedupe instead (v3.0.4): if it cleans the playlist and
# records a mapping, the run continues to the mapping check
# and the normal steps (the later dedupe step then no-ops);
# if it fails, the run stops before shuffle/rediscover.
if [ -n "${SETER_DAILY_DRY_RUN:-}" ]; then
  log "dry run: auto self-probes skipped (dry runs change nothing); planned probes: '$PLAYLIST', '$REDISCOVER_PLAYLIST'"
else
  probe_status=0
  auto_self_probe "$PLAYLIST" || probe_status=$?
  if [ "$probe_status" = "2" ]; then
    log "daily trial-dedupe attempt for '$PLAYLIST' (probe refused on duplicates)"
    if "$ROOT/run.sh" dedupe "$PLAYLIST" >> "$LOG" 2>&1; then
      log "daily trial-dedupe cleaned '$PLAYLIST'; continuing to the mapping check"
    else
      log "DAILY FAILED: trial-dedupe failed for '$PLAYLIST'; daily stopped before shuffle and rediscover"
      exit 1
    fi
  elif [ "$probe_status" != "0" ]; then
    exit 1
  fi
  auto_self_probe "$REDISCOVER_PLAYLIST" || exit 1
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
