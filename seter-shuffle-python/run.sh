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
# Every step checks its exit code; on any failure the run stops and the
# playlist is left as the apply script left it (restored from backup
# when the apply step itself failed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BRIDGE="$ROOT/bridge"
STATE="$HOME/Library/Logs/seter-shuffle-python"
LOG="$STATE/run.log"
HISTORY="$HOME/Documents/SeTeRShuffle/rediscover-history.tsv"

mkdir -p "$STATE"
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

# 1. A real python3, or fail loudly before Music is touched.
# check-python.sh prints "<path> (<version>)" on stdout; only the path
# is used as the interpreter.
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

# Undo needs no dump: it only replays a backup file.
if [ "$CMD" = "undo" ]; then
  PLAYLIST="${2:-}"
  [ -n "$PLAYLIST" ] || { echo "usage: $0 undo <playlist>" >&2; exit 2; }
  BACKUP="$STATE/backup-$(echo "$PLAYLIST" | tr ' /' '__').txt"
  log "undo $PLAYLIST from $BACKUP"
  osascript "$BRIDGE/undo.applescript" "$PLAYLIST" "$BACKUP" | tee -a "$LOG"
  log "undo done"
  exit 0
fi

# Dump: whole library, or one playlist for shuffle.
if [ "$CMD" = "shuffle" ] && [ -n "${2:-}" ]; then
  SOURCE_PLAYLIST="$2"
  TARGET_PLAYLIST="$2"
  log "dumping playlist $SOURCE_PLAYLIST"
  osascript "$BRIDGE/dump-library.applescript" "$DUMP" "$SOURCE_PLAYLIST" | tee -a "$LOG"
else
  log "dumping library"
  osascript "$BRIDGE/dump-library.applescript" "$DUMP" | tee -a "$LOG"
fi

export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
case "$CMD" in
  audit)
    log "audit (no Music changes)"
    "$PY" -m seter_shuffle.cli audit --library "$DUMP" | tee -a "$LOG"
    log "audit done; nothing was applied"
    ;;
  flowPreview)
    log "flowPreview (no Music changes)"
    "$PY" -m seter_shuffle.cli flowPreview --library "$DUMP" --out "$ORDER" --order-txt "$ORDER_TXT" | tee -a "$LOG"
    log "flowPreview done; nothing was applied"
    ;;
  flow)
    TARGET_PLAYLIST="SeTeR Flow"
    "$PY" -m seter_shuffle.cli flow --library "$DUMP" --out "$ORDER" --order-txt "$ORDER_TXT" | tee -a "$LOG"
    BACKUP="$STATE/backup-SeTeR-Flow.txt"
    log "applying to $TARGET_PLAYLIST (backup $BACKUP)"
    osascript "$BRIDGE/apply-order.applescript" "$TARGET_PLAYLIST" "$ORDER_TXT" "$BACKUP" | tee -a "$LOG"
    log "flow done"
    ;;
  shuffle)
    TARGET_PLAYLIST="${TARGET_PLAYLIST:-SeTeR Shuffle}"
    "$PY" -m seter_shuffle.cli shuffle --library "$DUMP" --out "$ORDER" --order-txt "$ORDER_TXT" | tee -a "$LOG"
    BACKUP="$STATE/backup-$(echo "$TARGET_PLAYLIST" | tr ' /' '__').txt"
    log "applying to $TARGET_PLAYLIST (backup $BACKUP)"
    osascript "$BRIDGE/apply-order.applescript" "$TARGET_PLAYLIST" "$ORDER_TXT" "$BACKUP" | tee -a "$LOG"
    log "shuffle done"
    ;;
  rediscover-preview)
    log "rediscover-preview (no Music changes)"
    "$PY" -m seter_shuffle.cli rediscover-preview --library "$DUMP" --history "$HISTORY" --out "$ORDER" --order-txt "$ORDER_TXT" | tee -a "$LOG"
    log "rediscover-preview done; nothing was applied, history untouched"
    ;;
  rediscover)
    TARGET_PLAYLIST="SeTeR Rediscover"
    "$PY" -m seter_shuffle.cli rediscover --library "$DUMP" --history "$HISTORY" --out "$ORDER" --order-txt "$ORDER_TXT" | tee -a "$LOG"
    BACKUP="$STATE/backup-SeTeR-Rediscover.txt"
    log "applying to $TARGET_PLAYLIST (backup $BACKUP)"
    osascript "$BRIDGE/apply-order.applescript" "$TARGET_PLAYLIST" "$ORDER_TXT" "$BACKUP" | tee -a "$LOG"
    # History is recorded ONLY now, after a successful apply, so a
    # failed apply never burns a song's cooldown.
    "$PY" -m seter_shuffle.cli record-history --history "$HISTORY" --ids-file "$ORDER_TXT" | tee -a "$LOG"
    log "rediscover done"
    ;;
esac
