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
backup_path_for() {
  local name="$1" safe hash
  safe="$(printf '%s' "$name" | tr ' /' '__')"
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
  audit|flowPreview|flow|shuffle|rediscover-preview|rediscover|undo) ;;
  *)
    echo "usage: $0 {audit|flowPreview|flow|shuffle [playlist]|rediscover-preview|rediscover|undo <playlist>}" >&2
    exit 2
    ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DUMP="$WORK/library.json"
ORDER="$WORK/order.json"
ORDER_TXT="$WORK/order.txt"

# Undo needs no dump: it only replays a backup file. The undo script
# itself snapshots the current playlist to <backup>.pre-undo before
# deleting anything, so a failed undo is recoverable.
if [ "$CMD" = "undo" ]; then
  PLAYLIST="${2:-}"
  [ -n "$PLAYLIST" ] || { echo "usage: $0 undo <playlist>" >&2; exit 2; }
  BACKUP="$(backup_path_for "$PLAYLIST")"
  log "undo $PLAYLIST from $BACKUP (pre-undo snapshot will be saved at $BACKUP.pre-undo)"
  step "undo $PLAYLIST" osascript "$BRIDGE/undo.applescript" "$PLAYLIST" "$BACKUP" || exit 1
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
# is the runner's half: catch a bad order before Music is touched,
# and recover if the apply step itself fails after changes start.
apply_order() {
  local target="$1" mode="$2" backup lib_songs
  backup="$(backup_path_for "$target")"
  step "validate order ($mode) for $target" "$PY" -m seter_shuffle.cli validate-order --library "$DUMP" --order-txt "$ORDER_TXT" --order-json "$ORDER" --mode "$mode" || exit 1
  log "GATE: order validated for $target"
  lib_songs="$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d["tracks"]))' "$DUMP")" || { log "GATE FAILED: could not count songs in dump"; exit 1; }
  # Preserve the previous backup, then clear the path, so that after
  # this point the presence of the backup file proves this run wrote
  # a fresh one. Without this, a failed apply could "restore" from a
  # stale backup and revert the playlist to an older state.
  if [ -f "$backup" ]; then
    cp "$backup" "$backup.prev"
    log "previous backup preserved at $backup.prev"
    rm -f "$backup"
  fi
  if step "apply order to $target" osascript "$BRIDGE/apply-order.applescript" "$target" "$ORDER_TXT" "$backup" "$lib_songs"; then
    log "GATE: apply verified for $target (backup at $backup)"
  else
    log "GATE FAILED: apply failed for $target"
    if [ -f "$backup" ]; then
      log "fresh backup exists at $backup; attempting restore via undo"
      if step "restore $target from fresh backup" osascript "$BRIDGE/undo.applescript" "$target" "$backup"; then
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
    step "compute shuffle order" "$PY" -m seter_shuffle.cli shuffle --library "$DUMP" --out "$ORDER" --order-txt "$ORDER_TXT" || exit 1
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
