#!/bin/bash
# run.sh (SeTeR Shuffle, Python experimental core)
#
# Wires the pieces together: AppleScript bridge -> Python core -> bridge.
# The Python core never touches Music; the bridge never decides an
# order. Previews never call the apply script at all.
#
# Usage (from this directory):
#   ./run.sh audit                  tag-coverage audit, change nothing
#   ./run.sh flowPreview            print the would-be Flow order, change nothing
#   ./run.sh flow                   build/refresh "SeTeR Flow"
#   ./run.sh shuffle [playlist]     shuffle a playlist in place, or the
#                                   whole library into "SeTeR Shuffle"
#   ./run.sh rediscover-preview     print Rediscover picks, change nothing
#   ./run.sh rediscover             refresh "SeTeR Rediscover" and record
#                                   history ONLY after a successful apply
#   ./run.sh undo <playlist>        restore a playlist from its last backup
#   ./run.sh probe                  (legacy) measure direction on a
#                                   fresh 3-song probe playlist; a
#                                   standalone sanity check ONLY, no
#                                   build consults it anymore
#   ./run.sh sortprobe <throwaway>  measure the build-to-list mapping
#                                   on a throwaway YOU set to the
#                                   same sort as the target playlist
#                                   (Playlist Order descending for
#                                   the 2026-10-28 failure); snapshots
#                                   the throwaway, builds a rotation,
#                                   reads it back, restores it, and
#                                   records the mapping for builds
#                                   (fresh for 24 hours)
#   ./run.sh probe-keep             like probe, but LEAVE the probe
#                                   playlist in place so its on-screen
#                                   order in Music can be eyeballed
#                                   against the probe verdict, then
#                                   delete it in Music when done
#
# BUILD MAPPING (2026-10-28 failure, 2026-10-29 diagnosis): the .4
# bridge failed verification in a loop on a real 806-song playlist,
# and the .5 bridge failed the same way even though a fresh 3-song
# probe reported "forward": a fresh playlist does not share the
# real playlist's sort (the user confirmed the real playlist is
# sorted by Playlist Order descending). A later diagnostic also
# killed track index as a manual-order reference (list read
# reversed against the backup, yet the list's first track carries
# index 1). So builds below NEVER consult a fresh probe and NEVER
# use track index. Instead, the user first runs ./run.sh sortprobe
# on a throwaway set to the SAME sort as the target; sort-probe
# builds a rotation on it, reads it back, restores it, and records
# the end-to-end mapping (forward: building X lands list read X;
# reversed: building X lands list read reverse(X)). Apply and undo
# read that recorded mapping (fresh for 24 hours, else they refuse)
# and pass it to the bridge scripts, which build and verify with it
# (see bridge/sort-probe.applescript and
# seter_shuffle/order_direction.py's mapping section). A sort-probe
# that returns anything else refuses the build upstream. There is
# no flip-on-failure fallback anywhere in the normal flow, and the
# old probe-order script is a standalone sanity check only: its
# verdict can never override a sort-matched mapping, because no
# build reads it.
#
# State lives under ~/Library/Logs/seter-shuffle-python/ on the Mac:
# dumps, orders, backups, and the run log. Nothing here touches the
# stable AppleScript install (~/Documents/SeTeRShuffle) or its launchd
# job. This is opt-in experimental only.
#
# Safety wiring (see BRIDGE-SAFETY.md for the full contract):
#  * Every step runs through step(), which logs GATE OK / GATE FAILED
#    and stops the run on failure. No step can silently continue
#    after a failed step, and both stdout AND stderr go to the log,
#    so a failure leaves evidence of which gate fired.
#  * An order is validated (validate-order) after the core computes
#    it and before the bridge ever runs: empty, duplicate,
#    missing-ID, truncated, or wrong-count orders are refused while
#    the playlist is still untouched.
#  * Before an apply, any previous backup is preserved as
#    <backup>.prev and the backup path is cleared, so a stale backup
#    can never be mistaken for this run's fresh backup. If the apply
#    then fails AND a fresh backup exists, the runner attempts a
#    restore from it via undo before exiting non-zero. If no fresh
#    backup exists, the apply failed before any playlist change, and
#    the log says so instead of restoring from a stale file.
#  * Backup filenames include a hash of the playlist name, so two
#    playlists whose names differ only by spaces and slashes can no
#    longer share a backup file (an old quirk: the old names were
#    sanitized only). Backup files from before this change still
#    exist under their old names and can be used by calling
#    undo.applescript directly with that file.
#  * Rediscover history is recorded ONLY after a successful apply,
#    so a failed apply never burns a song's cooldown.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BRIDGE="$ROOT/bridge"
STATE="$HOME/Library/Logs/seter-shuffle-python"
LOG="$STATE/run.log"
HISTORY="$HOME/Documents/SeTeRShuffle/rediscover-history.tsv"

mkdir -p "$STATE"
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

# Run one step, logging its output (stdout and stderr) and its gate
# result. Returns non-zero on failure; with set -e, a bare step call
# stops the run, and a step call inside an if-condition lets the
# caller handle the failure (used for the apply step, below).
step() {
  local label="$1"; shift
  log "STEP: $label"
  if "$@" 2>&1 | tee -a "$LOG"; then
    log "GATE OK: $label"
  else
    log "GATE FAILED: $label"
    return 1
  fi
}

# Backup filename for a playlist: sanitized name plus a hash of the
# full name, so distinct names can never collide after sanitizing.
# Newlines and carriage returns are also neutralized first: a
# playlist name can legally contain them, and a newline in a
# filename would break log lines that name the backup file.
backup_path_for() {
  local name="$1" safe hash
  safe="$(printf '%s' "$name" | tr '\n\r' '__' | tr ' /' '__')"
  if command -v shasum >/dev/null 2>&1; then
    hash="$(printf '%s' "$name" | shasum -a 256 | cut -c1-12)"
  elif command -v md5 >/dev/null 2>&1; then
    hash="$(printf '%s' "$name" | md5 | cut -c1-12)"
  else
    hash="nohash"
  fi
  printf '%s/backup-%s-%s.txt' "$STATE" "$safe" "$hash"
}

# 1. A real python3, or fail loudly before Music is touched.
# check-python.sh prints "<path> (<version>)" on stdout; only the path
# is used as the interpreter. Paths with spaces are refused by
# check-python.sh itself, so this split is safe.
CHECK_OUT="$(bash "$ROOT/check-python.sh")" || exit 2
PY="${CHECK_OUT%% *}"
log "python: $CHECK_OUT"

CMD="${1:-}"
case "$CMD" in
  audit|flowPreview|flow|shuffle|rediscover-preview|rediscover|undo|probe|probe-keep|sortprobe) ;;
  *)
    echo "usage: $0 {audit|flowPreview|flow|shuffle [playlist]|rediscover-preview|rediscover|undo <playlist>|probe|probe-keep|sortprobe <throwaway>}" >&2
    exit 2
    ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DUMP="$WORK/library.json"
ORDER="$WORK/order.json"
ORDER_TXT="$WORK/order.txt"

# Log-file-only logging: probe_mode runs inside a command
# substitution whose stdout is captured as the mode, so its STEP /
# GATE lines must go to the log file only, never to stdout, or they
# would corrupt the captured mode string.
logfile() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

# Measure this Mac's playlist order direction on a fresh timestamped
# probe playlist, and print exactly one mode word to stdout. The
# probe script deletes its own playlist and reports PROBE_CLEANUP_OK;
# anything else (ambiguous verdict, missing cleanup, probe failure)
# is a failed gate: the caller must exit without touching a real
# playlist. A leftover "SeTeR Probe *" playlist after a failure
# means the probe's own delete failed; delete it in Music by hand.
probe_mode() {
  local probe_name verdict
  probe_name="SeTeR Probe $(date +%s)"
  logfile "STEP: probe playlist order"
  if osascript "$BRIDGE/probe-order.applescript" "$probe_name" >"$WORK/probe.out" 2>&1; then
    cat "$WORK/probe.out" >> "$LOG"
    verdict="$(grep '^PROBE_VERDICT: ' "$WORK/probe.out" | head -n 1 | sed 's/^PROBE_VERDICT: //')"
    if grep -q '^PROBE_CLEANUP_OK$' "$WORK/probe.out" && { [ "$verdict" = "forward" ] || [ "$verdict" = "insert-reversed" ] || [ "$verdict" = "read-reversed" ]; }; then
      logfile "GATE OK: probe playlist order ($verdict)"
      printf '%s' "$verdict"
      return 0
    fi
  else
    cat "$WORK/probe.out" >> "$LOG" 2>/dev/null || true
  fi
  logfile "GATE FAILED: probe playlist order (ambiguous or failed; real playlist untouched; delete any leftover 'SeTeR Probe *' playlist in Music if one remains)"
  return 1
}

# Probe commands need no dump: they only measure direction.
if [ "$CMD" = "probe" ]; then
  MODE="$(probe_mode)" || exit 1
  cat "$WORK/probe.out"
  log "probe mode: $MODE"
  exit 0
fi
if [ "$CMD" = "probe-keep" ]; then
  probe_name="SeTeR Probe $(date +%s)"
  log "STEP: probe playlist order (kept)"
  # Not run through step(): a completed probe exits 0 even when its
  # verdict is ambiguous (so its lines reach the log), and an
  # ambiguous kept probe must still fail the gate here.
  if osascript "$BRIDGE/probe-order.applescript" "$probe_name" "keep" 2>&1 | tee -a "$LOG" "$WORK/probe.out"; then
    verdict="$(grep '^PROBE_VERDICT: ' "$WORK/probe.out" | head -n 1 | sed 's/^PROBE_VERDICT: //')"
    if [ "$verdict" = "forward" ] || [ "$verdict" = "insert-reversed" ] || [ "$verdict" = "read-reversed" ]; then
      log "GATE OK: probe playlist order (kept, $verdict)"
      log "probe playlist '$probe_name' left in place: check its on-screen order in Music against the verdict above, then delete it in Music when done"
      exit 0
    fi
  fi
  log "GATE FAILED: probe playlist order (kept, ambiguous or failed); delete the probe playlist in Music if one remains"
  exit 1
fi

# Read the recorded sort-matched mapping for builds, or refuse.
# sortprobe writes $STATE/sort-mapping.txt with lines:
#   MAPPING: forward|reversed
#   THROWAWAY: <name the user set to the target's sort>
#   TIMESTAMP: <epoch seconds>
# Builds refuse without it, refuse a stale one (older than 24h),
# and log the source, so a build never silently uses a mapping
# measured for a different sort or a different day. If the target's
# sort may have changed since the probe, re-run sortprobe first:
# a stale mapping is a wrong mapping.
mapping_for_build() {
  local map_file="$STATE/sort-mapping.txt" mapping throwaway ts now
  if [ ! -f "$map_file" ]; then
    log "GATE FAILED: no sort-matched mapping recorded; run ./run.sh sortprobe <throwaway> on a throwaway set to the target's sort first"
    return 1
  fi
  mapping="$(grep '^MAPPING: ' "$map_file" | head -n 1 | sed 's/^MAPPING: //')"
  throwaway="$(grep '^THROWAWAY: ' "$map_file" | head -n 1 | sed 's/^THROWAWAY: //')"
  ts="$(grep '^TIMESTAMP: ' "$map_file" | head -n 1 | sed 's/^TIMESTAMP: //')"
  now="$(date +%s)"
  if [ "$mapping" != "forward" ] && [ "$mapping" != "reversed" ]; then
    log "GATE FAILED: recorded mapping is not forward or reversed (got '$mapping'); re-run sortprobe"
    return 1
  fi
  case "$ts" in ''|*[!0-9]*) log "GATE FAILED: recorded mapping has no valid timestamp; re-run sortprobe"; return 1;; esac
  if [ $((now - ts)) -gt 86400 ]; then
    log "GATE FAILED: recorded mapping is older than 24 hours (throwaway '$throwaway'); re-run sortprobe so the mapping matches the target's current sort"
    return 1
  fi
  log "sort mapping for builds: $mapping (measured on throwaway '$throwaway' at $(date -r "$ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$ts"))"
  printf '%s' "$mapping"
  return 0
}

# Sort-probe command: measure the mapping on a user-sorted throwaway.
# The user MUST set the throwaway's sort in Music to the target's
# sort (Playlist Order descending for the 2026-10-28 failure)
# before running this; run.sh cannot set or verify a playlist's
# UI sort, so a throwaway with the wrong sort measures the wrong
# mapping, and the log line below says exactly what was assumed.
if [ "$CMD" = "sortprobe" ]; then
  THROWAWAY="${2:-}"
  [ -n "$THROWAWAY" ] || { echo "usage: $0 sortprobe <throwaway-playlist>" >&2; exit 2; }
  SNAPSHOT="$STATE/sort-probe-snapshot.txt"
  log "STEP: sort-probe mapping on throwaway '$THROWAWAY' (assumed sort: same as target; set it in Music before running)"
  if osascript "$BRIDGE/sort-probe.applescript" "$THROWAWAY" "$SNAPSHOT" 2>&1 | tee -a "$LOG" "$WORK/sortprobe.out"; then
    mapping="$(grep '^MAPPING: ' "$WORK/sortprobe.out" | head -n 1 | sed 's/^MAPPING: //')"
    if [ "$mapping" = "forward" ] || [ "$mapping" = "reversed" ]; then
      {
        printf 'MAPPING: %s\n' "$mapping"
        printf 'THROWAWAY: %s\n' "$THROWAWAY"
        printf 'TIMESTAMP: %s\n' "$(date +%s)"
      } > "$STATE/sort-mapping.txt"
      log "GATE OK: sort-probe mapping $mapping recorded for builds (valid 24 hours; throwaway '$THROWAWAY')"
      log "sortprobe done; throwaway restored to its snapshot; verify it in Music if you want, then run the build"
      exit 0
    fi
  fi
  log "GATE FAILED: sort-probe did not return a usable mapping; no mapping recorded, no build will run until a clean sort-probe passes"
  exit 1
fi

# Undo needs no dump: it only replays a backup file. The undo script
# itself snapshots the current playlist to <backup>.pre-undo before
# deleting anything, so a failed undo is recoverable. It builds
# under the recorded sort-matched mapping; without a fresh mapping
# it refuses, because an unmapped undo is exactly how the .4/.5
# loops failed.
if [ "$CMD" = "undo" ]; then
  PLAYLIST="${2:-}"
  [ -n "$PLAYLIST" ] || { echo "usage: $0 undo <playlist>" >&2; exit 2; }
  BACKUP="$(backup_path_for "$PLAYLIST")"
  MAPPING="$(mapping_for_build)" || exit 1
  log "undo $PLAYLIST from $BACKUP (mapping $MAPPING; pre-undo snapshot will be saved at $BACKUP.pre-undo)"
  step "undo $PLAYLIST" osascript "$BRIDGE/undo.applescript" "$PLAYLIST" "$BACKUP" "$MAPPING" || exit 1
  log "undo done"
  exit 0
fi

# Dump: whole library, or one playlist for shuffle. The dump lives in
# a fresh temporary directory per run, so a failed dump can never
# leave a stale dump file for the next step to mistake for a new one.
if [ "$CMD" = "shuffle" ] && [ -n "${2:-}" ]; then
  SOURCE_PLAYLIST="$2"
  TARGET_PLAYLIST="$2"
  step "dump playlist $SOURCE_PLAYLIST" osascript "$BRIDGE/dump-library.applescript" "$DUMP" "$SOURCE_PLAYLIST" || exit 1
else
  step "dump library" osascript "$BRIDGE/dump-library.applescript" "$DUMP" || exit 1
fi

export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

# Validate an order, then apply it, with restore-on-failure. The
# bridge also validates and verifies on its own side; this function
# is the runner's half: read the recorded sort-matched mapping,
# catch a bad order before Music is touched, and recover if the
# apply step itself fails after changes start. The mapping is read
# before validation on purpose: a missing or stale mapping costs
# nothing, and an unmapped apply must never run.
apply_order() {
  local target="$1" mode="$2" backup lib_songs allow_dupes build_mapping
  local -a apply_args
  backup="$(backup_path_for "$target")"
  build_mapping="$(mapping_for_build)" || exit 1
  step "validate order ($mode) for $target" "$PY" -m seter_shuffle.cli validate-order --library "$DUMP" --order-txt "$ORDER_TXT" --order-json "$ORDER" --mode "$mode" || exit 1
  log "GATE: order validated for $target"
  # Duplicate allowance: "1" only for a one-playlist shuffle whose
  # dump itself repeats an ID (duplicate playlist entries, preserved
  # as positions). Every other mode refuses duplicate order IDs.
  # Library-song count: only for whole-library dumps. For a
  # one-playlist shuffle the dump count is a playlist count, and
  # passing it as a library count would compare the wrong things
  # (the .4 runner did exactly that); the bridge's mid-run
  # library-size check still applies in both cases.
  allow_dupes="0"
  lib_songs=""
  if [ -n "${SOURCE_PLAYLIST:-}" ]; then
    if "$PY" -c 'import json,sys; from collections import Counter; d=json.load(open(sys.argv[1])); ids=[t["persistent_id"] for t in d["tracks"]]; sys.exit(0 if len(ids) != len(set(ids)) else 1)' "$DUMP" 2>/dev/null; then
      allow_dupes="1"
    fi
  else
    lib_songs="$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d["tracks"]))' "$DUMP")" || { log "GATE FAILED: could not count songs in dump"; exit 1; }
  fi
  # Preserve the previous backup, then clear the path, so that after
  # this point the presence of the backup file proves this run wrote
  # a fresh one. Without this, a failed apply could "restore" from a
  # stale backup and revert the playlist to an older state.
  if [ -f "$backup" ]; then
    cp "$backup" "$backup.prev"
    log "previous backup preserved at $backup.prev"
    rm -f "$backup"
  fi
  if [ -n "$lib_songs" ]; then
    apply_args=("$target" "$ORDER_TXT" "$backup" "$build_mapping" "$allow_dupes" "$lib_songs")
  else
    apply_args=("$target" "$ORDER_TXT" "$backup" "$build_mapping" "$allow_dupes")
  fi
  if step "apply order to $target" osascript "$BRIDGE/apply-order.applescript" "${apply_args[@]}"; then
    log "GATE: apply verified for $target (backup at $backup)"
  else
    log "GATE FAILED: apply failed for $target"
    if [ -f "$backup" ]; then
      log "fresh backup exists at $backup; attempting restore via undo (same recorded mapping)"
      if step "restore $target from fresh backup" osascript "$BRIDGE/undo.applescript" "$target" "$backup" "$build_mapping"; then
        log "restore from fresh backup succeeded; playlist is back to its pre-run state"
      else
        log "CRITICAL: restore from fresh backup also failed; playlist may be partial; re-run undo with backup $backup"
      fi
    else
      log "no fresh backup was written, so the apply failed before any playlist change; playlist untouched"
    fi
    exit 1
  fi
}

case "$CMD" in
  audit)
    log "audit (no Music changes)"
    step "audit" "$PY" -m seter_shuffle.cli audit --library "$DUMP" || exit 1
    log "audit done; nothing was applied"
    ;;
  flowPreview)
    log "flowPreview (no Music changes)"
    step "flowPreview" "$PY" -m seter_shuffle.cli flowPreview --library "$DUMP" --out "$ORDER" --order-txt "$ORDER_TXT" || exit 1
    log "flowPreview done; nothing was applied"
    ;;
  flow)
    TARGET_PLAYLIST="SeTeR Flow"
    step "compute flow order" "$PY" -m seter_shuffle.cli flow --library "$DUMP" --out "$ORDER" --order-txt "$ORDER_TXT" || exit 1
    apply_order "$TARGET_PLAYLIST" "flow"
    log "flow done"
    ;;
  shuffle)
    TARGET_PLAYLIST="${TARGET_PLAYLIST:-SeTeR Shuffle}"
    # One-playlist shuffles pass --allow-duplicates (see the flag's
    # comment in cli.py): the dump repeats an ID for each duplicate
    # playlist entry, and those entries must be preserved. A
    # whole-library shuffle never passes it, so a repeated ID in a
    # library dump still fails closed.
    if [ -n "${SOURCE_PLAYLIST:-}" ]; then
      step "compute shuffle order" "$PY" -m seter_shuffle.cli shuffle --library "$DUMP" --out "$ORDER" --order-txt "$ORDER_TXT" --allow-duplicates || exit 1
    else
      step "compute shuffle order" "$PY" -m seter_shuffle.cli shuffle --library "$DUMP" --out "$ORDER" --order-txt "$ORDER_TXT" || exit 1
    fi
    apply_order "$TARGET_PLAYLIST" "shuffle"
    log "shuffle done"
    ;;
  rediscover-preview)
    log "rediscover-preview (no Music changes)"
    step "rediscover-preview" "$PY" -m seter_shuffle.cli rediscover-preview --library "$DUMP" --history "$HISTORY" --out "$ORDER" --order-txt "$ORDER_TXT" || exit 1
    log "rediscover-preview done; nothing was applied, history untouched"
    ;;
  rediscover)
    TARGET_PLAYLIST="SeTeR Rediscover"
    step "compute rediscover order" "$PY" -m seter_shuffle.cli rediscover --library "$DUMP" --history "$HISTORY" --out "$ORDER" --order-txt "$ORDER_TXT" || exit 1
    apply_order "$TARGET_PLAYLIST" "rediscover"
    # History is recorded ONLY now, after a successful apply, so a
    # failed apply never burns a song's cooldown.
    step "record rediscover history" "$PY" -m seter_shuffle.cli record-history --history "$HISTORY" --ids-file "$ORDER_TXT" || exit 1
    log "rediscover done"
    ;;
esac
