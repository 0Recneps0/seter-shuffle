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
#   ./run.sh dedupe <playlist>      remove duplicate entries from a
#                                   playlist (unique songs, first
#                                   occurrence order); skips the
#                                   apply entirely if it has none
#   ./run.sh restore <playlist> <backup-txt>
#                                   restore a playlist from a given
#                                   backup file (freshness-checked
#                                   mapping, same as undo)
#   ./run.sh probe                  (legacy) measure direction on a
#                                   fresh 3-song probe playlist; a
#                                   standalone sanity check ONLY, no
#                                   build consults it anymore
#   ./run.sh sortprobe <throwaway> <target> <sort-label>
#                                   measure the build-to-list mapping
#                                   on a throwaway YOU set to the
#                                   target's sort, and record it
#                                   PER-TARGET (a mapping for one
#                                   target never authorizes a build
#                                   on another); snapshots the
#                                   throwaway, builds a rotation,
#                                   reads it back, restores it, and
#                                   records the mapping for that
#                                   target's builds (fresh for 24
#                                   hours)
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
#  * Backups are per-run, never clobbered by a failed run (2026-10-29
#    doubling failure: the 00:41 run overwrote the main backup with
#    the doubled 1612-entry state, and only the .prev copy preserved
#    the original 806 order; one more failed run would have
#    overwritten .prev with the doubled state too). The apply script
#    writes its pre-change snapshot to a fresh per-run file
#    (<backup>.run-<timestamp>-<pid>.txt). Only AFTER a verified
#    successful apply is that file installed as the main backup
#    (previous main backup preserved as <backup>.prev). On an apply
#    failure, the restore attempt uses the per-run snapshot, and the
#    main backup is untouched, so a failed or partial run can never
#    leave the only good backup overwritten. Per-run snapshots are
#    kept (newest 10) as a chain, not deleted.
#  * A sort-probe failure deletes any recorded mapping, so a stale
#    mapping can never survive a failed re-probe and authorize a
#    build under an unknown sort.
#  * mapping_for_build logs with logfile() only, never log(): its
#    output is captured with $(...), and a log() line (tee to
#    stdout) would pollute the captured mapping string, which the
#    bridge would then refuse. The .1 runner had exactly this bug
#    (see BRIDGE-SAFETY.md mode 31): no build through run.sh could
#    have run at all, because every captured mapping carried a log
#    line in front of it.
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

# Mapping filename for a target playlist: same safe-name-plus-hash
# scheme as backups, so distinct targets can never share a mapping
# file. This is the .5 fix for the 2026-10-29 mapping-transfer
# failure: a Flow build reused a mapping measured on the main
# playlist (Playlist Order descending, reversed) for a brand-new
# "SeTeR Flow" playlist (default/manual sort, forward), landed
# backwards, and verify correctly refused it. Mappings are
# per-target since .5: a build for target X reads ONLY the mapping
# file for X, never a shared file, so a mapping measured for one
# playlist's sort cannot silently authorize a build on another.
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

# 1. A real python3, or fail loudly before Music is touched.
# check-python.sh prints "<path> (<version>)" on stdout; only the path
# is used as the interpreter. Paths with spaces are refused by
# check-python.sh itself, so this split is safe.
CHECK_OUT="$(bash "$ROOT/check-python.sh")" || exit 2
PY="${CHECK_OUT%% *}"
log "python: $CHECK_OUT"

CMD="${1:-}"
case "$CMD" in
  audit|flowPreview|flow|shuffle|rediscover-preview|rediscover|undo|dedupe|restore|probe|probe-keep|sortprobe) ;;
  *)
    echo "usage: $0 {audit|flowPreview|flow|shuffle [playlist]|rediscover-preview|rediscover|undo <playlist>|dedupe <playlist>|restore <playlist> <backup-txt>|probe|probe-keep|sortprobe <throwaway> <target> <sort-label>}" >&2
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

# Log to the file AND to stderr: for functions called inside $(...),
# where log() (tee to stdout) would pollute the captured value and
# logfile() would hide a failure from the terminal entirely. stderr
# is never captured by $(...), so a logerr line is visible on the
# terminal, recorded in the log, and can never enter a captured
# mapping or mode string. This is the .3 fix for the silent
# mapping-gate failure: a shuffle used to stop after "compute
# shuffle order" with no visible error when no mapping was recorded.
logerr() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG" >&2; }

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
  logerr "GATE FAILED: probe playlist order (ambiguous or failed; real playlist untouched; delete any leftover 'SeTeR Probe *' playlist in Music if one remains)"
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

# Read the recorded sort-matched mapping for one target, or refuse.
# sortprobe writes the per-target file from mapping_file_for with
# lines:
#   MAPPING: forward|reversed
#   THROWAWAY: <name the user set to the target's sort>
#   TARGET: <target playlist the mapping was measured for>
#   SORT: <sort label the user declared for the throwaway>
#   TIMESTAMP: <epoch seconds>
# Builds refuse without a mapping for THEIR target, refuse a stale
# one (older than 24h), and refuse a file whose TARGET field does
# not match, so a build never silently uses a mapping measured for
# a different playlist's sort or a different day. If the target's
# sort may have changed since the probe, re-run sortprobe first:
# a stale mapping is a wrong mapping.
# The pre-.5 shared file $STATE/sort-mapping.txt is IGNORED since
# .5: it is exactly the file that let a Flow build reuse a mapping
# measured on the main playlist's descending sort for a new
# default-sorted playlist (mode 35). If it exists and no per-target
# file does, the failure message says so explicitly instead of
# silently falling back to it.
# CRITICAL: this function is always called inside $(...) (its
# output IS the mapping), so it must NEVER write to stdout except
# the final mapping word. log() tees to stdout, which would pollute
# the captured mapping string and make the bridge refuse it. The .1
# runner logged with log() here, so no build through run.sh could
# run at all (mode 31): every captured mapping carried a log line
# in front of it. The .2 runner went to the other extreme and used
# logfile() for failures, which hid them from the terminal: a
# shuffle stopped after "compute shuffle order" with no visible
# error. The .3 rule is: failures go through logerr() (log file
# AND stderr, never stdout), success info stays logfile-only.
mapping_for_build() {
  local target="$1" map_file mapping throwaway recorded_target sort_label ts now
  map_file="$(mapping_file_for "$target")"
  if [ ! -f "$map_file" ]; then
    if [ -f "$STATE/sort-mapping.txt" ]; then
      logerr "GATE FAILED: no per-target sort mapping recorded for '$target'; the pre-.5 shared sort-mapping.txt is ignored since .5 because mappings do not transfer between sorts; run ./run.sh sortprobe <throwaway> '$target' '<sort-label>' on a throwaway set to '$target''s sort first"
    else
      logerr "GATE FAILED: no sort-matched mapping recorded for '$target'; run ./run.sh sortprobe <throwaway> '$target' '<sort-label>' on a throwaway set to '$target''s sort first"
    fi
    return 1
  fi
  mapping="$(grep '^MAPPING: ' "$map_file" | head -n 1 | sed 's/^MAPPING: //')"
  throwaway="$(grep '^THROWAWAY: ' "$map_file" | head -n 1 | sed 's/^THROWAWAY: //')"
  recorded_target="$(grep '^TARGET: ' "$map_file" | head -n 1 | sed 's/^TARGET: //')"
  sort_label="$(grep '^SORT: ' "$map_file" | head -n 1 | sed 's/^SORT: //')"
  ts="$(grep '^TIMESTAMP: ' "$map_file" | head -n 1 | sed 's/^TIMESTAMP: //')"
  now="$(date +%s)"
  if [ "$mapping" != "forward" ] && [ "$mapping" != "reversed" ]; then
    logerr "GATE FAILED: recorded mapping for '$target' is not forward or reversed (got '$mapping'); re-run sortprobe"
    return 1
  fi
  if [ "$recorded_target" != "$target" ]; then
    logerr "GATE FAILED: recorded mapping file for '$target' names target '$recorded_target'; mappings do not transfer between targets; re-run sortprobe for '$target'"
    return 1
  fi
  if [ -z "$sort_label" ]; then
    logerr "GATE FAILED: recorded mapping for '$target' has no sort label; re-run sortprobe with a sort label"
    return 1
  fi
  case "$ts" in ''|*[!0-9]*) logerr "GATE FAILED: recorded mapping for '$target' has no valid timestamp; re-run sortprobe"; return 1;; esac
  if [ $((now - ts)) -gt 86400 ]; then
    logerr "GATE FAILED: recorded mapping for '$target' is older than 24 hours (throwaway '$throwaway', sort '$sort_label'); re-run sortprobe so the mapping matches the target's current sort"
    return 1
  fi
  logfile "sort mapping for builds: $mapping (target '$target', throwaway '$throwaway', sort '$sort_label', at $(date -r "$ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$ts"))"
  printf '%s' "$mapping"
  return 0
}

# Print the recorded mapping's provenance to the terminal and the
# log (via log(), NOT captured, so stdout pollution is impossible
# here). Callers run this right after capturing the mapping, so a
# mismatch between the mapping's sort label and the target's actual
# sort is visible in the GATE lines BEFORE any build starts. This
# is the .5 visibility half of the mapping-transfer fix: run.sh
# cannot read a playlist's UI sort from Music, so the label the
# user declared at sortprobe time is the checkable record, and it
# must be on screen, not buried in the state directory.
mapping_info_for() {
  local target="$1" map_file mapping throwaway sort_label
  map_file="$(mapping_file_for "$target")"
  mapping="$(grep '^MAPPING: ' "$map_file" | head -n 1 | sed 's/^MAPPING: //')"
  throwaway="$(grep '^THROWAWAY: ' "$map_file" | head -n 1 | sed 's/^THROWAWAY: //')"
  sort_label="$(grep '^SORT: ' "$map_file" | head -n 1 | sed 's/^SORT: //')"
  log "build mapping for '$target': $mapping (throwaway '$throwaway', sort '$sort_label'); if this sort does not match '$target''s sort in Music, stop and re-run sortprobe"
}

# Sort-probe command: measure the mapping on a user-sorted throwaway
# FOR ONE TARGET. Since .5 the target and the sort label are
# required arguments, and the mapping is recorded per-target
# (mapping_file_for): a mapping measured for target X can never
# authorize a build on target Y. The user MUST set the throwaway's
# sort in Music to the target's sort before running this; run.sh
# cannot set or verify a playlist's UI sort, so a throwaway with
# the wrong sort measures the wrong mapping, and the STEP line
# below records exactly what was declared. Worked example of why
# this matters (2026-10-29, mode 35): the main playlist sorts
# Playlist Order descending (mapping reversed), while a brand-new
# "SeTeR Flow" playlist sorts default/manual (mapping forward);
# reusing the main playlist's mapping for Flow landed backwards
# and verify correctly refused it. Flow therefore needs its OWN
# sortprobe, on a throwaway set to SeTeR Flow's sort, before any
# Flow build, even when a main-playlist mapping already exists.
if [ "$CMD" = "sortprobe" ]; then
  THROWAWAY="${2:-}"
  PROBE_TARGET="${3:-}"
  PROBE_SORT="${4:-}"
  if [ -z "$THROWAWAY" ] || [ -z "$PROBE_TARGET" ] || [ -z "$PROBE_SORT" ]; then
    echo "usage: $0 sortprobe <throwaway-playlist> <target-playlist> <sort-label>" >&2
    echo "  example: $0 sortprobe 'Throwaway' 'My New Sandwich Recipe' 'Playlist Order descending'" >&2
    echo "  the throwaway must be set in Music to the target's sort BEFORE running; the sort label is your declaration of that sort, e.g. 'Playlist Order descending', 'Playlist Order ascending', or 'Manual (default)'" >&2
    exit 2
  fi
  SNAPSHOT="$STATE/sort-probe-snapshot.txt"
  MAP_FILE="$(mapping_file_for "$PROBE_TARGET")"
  log "STEP: sort-probe mapping on throwaway '$THROWAWAY' for target '$PROBE_TARGET' (declared sort: '$PROBE_SORT'; set the throwaway to this sort in Music before running)"
  if osascript "$BRIDGE/sort-probe.applescript" "$THROWAWAY" "$SNAPSHOT" 2>&1 | tee -a "$LOG" "$WORK/sortprobe.out"; then
    mapping="$(grep '^MAPPING: ' "$WORK/sortprobe.out" | head -n 1 | sed 's/^MAPPING: //')"
    if [ "$mapping" = "forward" ] || [ "$mapping" = "reversed" ]; then
      {
        printf 'MAPPING: %s\n' "$mapping"
        printf 'THROWAWAY: %s\n' "$THROWAWAY"
        printf 'TARGET: %s\n' "$PROBE_TARGET"
        printf 'SORT: %s\n' "$PROBE_SORT"
        printf 'TIMESTAMP: %s\n' "$(date +%s)"
      } > "$MAP_FILE.tmp"
      mv -f "$MAP_FILE.tmp" "$MAP_FILE"
      log "GATE OK: sort-probe mapping $mapping recorded for target '$PROBE_TARGET' (valid 24 hours; throwaway '$THROWAWAY', sort '$PROBE_SORT')"
      log "sortprobe done; throwaway restored to its snapshot; verify it in Music if you want, then run the build for '$PROBE_TARGET'"
      exit 0
    fi
  fi
  # Fail-closed on the mapping itself: a failed re-probe must not
  # leave a previous (possibly wrong-sort) mapping in place for a
  # build to pick up. Delete the PER-TARGET file, and say so, so
  # the next build for this target refuses until a clean
  # sort-probe passes. Other targets' mappings are untouched: a
  # failed probe for one target never invalidates another's.
  rm -f "$MAP_FILE"
  log "GATE FAILED: sort-probe did not return a usable mapping; any previously recorded mapping for target '$PROBE_TARGET' was deleted, no build for that target will run until a clean sort-probe passes"
  log "check the throwaway '$THROWAWAY' in Music: if the probe could not restore it, its snapshot is at $SNAPSHOT"
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
  if [ ! -f "$BACKUP" ]; then
    log "GATE FAILED: no backup file at $BACKUP, so undo refuses rather than deleting the playlist first and discovering it afterwards"
    log "recent backups in $STATE (use ./run.sh restore <playlist> <backup-txt> for one of these):"
    ls -t "$STATE"/backup-*.txt 2>/dev/null | head -n 10 | while read -r f; do log "  $f"; done
    exit 1
  fi
  MAPPING="$(mapping_for_build "$PLAYLIST")" || exit 1
  mapping_info_for "$PLAYLIST"
  log "undo $PLAYLIST from $BACKUP (mapping $MAPPING; pre-undo snapshot will be saved at $BACKUP.pre-undo)"
  step "undo $PLAYLIST" osascript "$BRIDGE/undo.applescript" "$PLAYLIST" "$BACKUP" "$MAPPING" || exit 1
  log "undo done"
  exit 0
fi

# Restore from an explicit backup file, through the same gate as
# undo: a freshness-checked sort-matched mapping, and a backup
# file that must exist before anything is deleted. This is the
# only supported way to call restore-original.applescript: a direct
# osascript call to it bypasses the freshness check (the script
# cannot know when the mapping was measured), so direct calls are
# expert-only and must be given a mapping measured within 24 hours
# on a throwaway carrying the target's sort.
if [ "$CMD" = "restore" ]; then
  PLAYLIST="${2:-}"
  BACKUP="${3:-}"
  [ -n "$PLAYLIST" ] && [ -n "$BACKUP" ] || { echo "usage: $0 restore <playlist> <backup-txt>" >&2; exit 2; }
  if [ ! -f "$BACKUP" ]; then
    log "GATE FAILED: backup file $BACKUP does not exist; restore refuses, playlist untouched"
    exit 1
  fi
  MAPPING="$(mapping_for_build "$PLAYLIST")" || exit 1
  mapping_info_for "$PLAYLIST"
  log "restore $PLAYLIST from $BACKUP (mapping $MAPPING; pre-fix snapshot will be saved at $BACKUP.fix-snapshot)"
  step "restore $PLAYLIST" osascript "$BRIDGE/restore-original.applescript" "$PLAYLIST" "$BACKUP" "$MAPPING" || exit 1
  log "restore done"
  exit 0
fi

# Dump: whole library, or one playlist for shuffle/dedupe. The dump
# lives in a fresh temporary directory per run, so a failed dump can
# never leave a stale dump file for the next step to mistake for a
# new one. Dedupe requires a playlist: deduping the whole library
# makes no sense (a library holds each song once by definition),
# and a library dump has no duplicate entries to remove.
if [ "$CMD" = "dedupe" ]; then
  [ -n "${2:-}" ] || { echo "usage: $0 dedupe <playlist>" >&2; exit 2; }
  SOURCE_PLAYLIST="$2"
  TARGET_PLAYLIST="$2"
  step "dump playlist $SOURCE_PLAYLIST" osascript "$BRIDGE/dump-library.applescript" "$DUMP" "$SOURCE_PLAYLIST" || exit 1
elif [ "$CMD" = "shuffle" ] && [ -n "${2:-}" ]; then
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
#
# BACKUP CHAIN (2026-10-29 doubling failure): the apply script
# writes its pre-change snapshot to a FRESH PER-RUN file, never to
# the main backup path. Only after a verified successful apply is
# that file installed as the main backup (previous main backup
# preserved as <backup>.prev). A failed or partial run therefore
# can never overwrite the main backup with a corrupted state: the
# 00:41 run overwrote the main backup with the doubled 1612-entry
# state and only .prev saved the original, and one more failed run
# would have overwritten .prev too. Per-run snapshots are kept
# (newest 10) as a chain, so recovery never depends on a single
# previous file.
apply_order() {
  local target="$1" mode="$2" backup run_backup lib_songs allow_dupes build_mapping
  local -a apply_args
  backup="$(backup_path_for "$target")"
  run_backup="${backup%.txt}.run-$(date +%Y%m%d-%H%M%S)-$$.txt"
  build_mapping="$(mapping_for_build "$target")" || exit 1
  mapping_info_for "$target"
  step "validate order ($mode) for $target" "$PY" -m seter_shuffle.cli validate-order --library "$DUMP" --order-txt "$ORDER_TXT" --order-json "$ORDER" --mode "$mode" || exit 1
  log "GATE: order validated for $target"
  # Duplicate allowance: "1" only for a one-playlist shuffle whose
  # dump itself repeats an ID (duplicate playlist entries, preserved
  # as positions). Every other mode refuses duplicate order IDs.
  # Dedupe forces "0" even though its dump repeats IDs: the dedupe
  # order itself is unique by construction, and allowing duplicates
  # there would weaken the bridge's second check for no reason.
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
  if [ "$mode" = "dedupe" ]; then
    allow_dupes="0"
  fi
  if [ -n "$lib_songs" ]; then
    apply_args=("$target" "$ORDER_TXT" "$run_backup" "$build_mapping" "$allow_dupes" "$lib_songs")
  else
    apply_args=("$target" "$ORDER_TXT" "$run_backup" "$build_mapping" "$allow_dupes")
  fi
  if step "apply order to $target" osascript "$BRIDGE/apply-order.applescript" "${apply_args[@]}"; then
    # Install the per-run snapshot as the main backup ONLY now,
    # after a verified success. The previous main backup is kept
    # as .prev, and the per-run file itself is kept too, so the
    # chain is: main backup, .prev, and the newest 10 run files.
    if [ -f "$backup" ]; then
      cp "$backup" "$backup.prev"
      log "previous backup preserved at $backup.prev"
    fi
    cp "$run_backup" "$backup"
    log "GATE: apply verified for $target (pre-run snapshot installed as backup at $backup; per-run snapshot kept at $run_backup)"
    # Prune old per-run snapshots, best-effort: a pruning failure
    # must never fail an already-successful apply.
    ls -t "$STATE"/backup-*.run-*.txt 2>/dev/null | tail -n +11 | while read -r f; do rm -f "$f"; done || true
  else
    log "GATE FAILED: apply failed for $target"
    if [ -f "$run_backup" ]; then
      log "per-run snapshot exists at $run_backup; attempting restore via undo (same recorded mapping); main backup at $backup was NOT overwritten by this failed run"
      if step "restore $target from per-run snapshot" osascript "$BRIDGE/undo.applescript" "$target" "$run_backup" "$build_mapping"; then
        log "restore from per-run snapshot succeeded; playlist is back to its pre-run state"
      else
        # Distinguish undo-failed-before-any-change from
        # undo-failed-after-changes (2026-10-29, mode 36): undo
        # marks pre-change failures with PLAYLIST_UNTOUCHED. Only
        # lines since this restore's STEP line count, so an older
        # run's marker cannot false-positive here. A pre-change
        # failure means the playlist was never touched, and saying
        # "may be partial" for it (as .4 did) is wrong and scary.
        restore_step_line="$(grep -n "STEP: restore $target from per-run snapshot" "$LOG" | tail -n 1 | cut -d: -f1)"
        if [ -n "$restore_step_line" ] && tail -n +"$restore_step_line" "$LOG" | grep -q "PLAYLIST_UNTOUCHED"; then
          log "restore from per-run snapshot failed while reading the playlist before any change (PLAYLIST_UNTOUCHED); playlist is untouched, NOT partial; re-run undo with backup $run_backup (main backup at $backup is still the last good state)"
        else
          log "CRITICAL: restore from per-run snapshot also failed; playlist may be partial; re-run undo with backup $run_backup (main backup at $backup is still the last good state)"
        fi
      fi
    else
      log "no per-run snapshot was written, so the apply failed before any playlist change; playlist untouched and main backup at $backup untouched"
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
  dedupe)
    TARGET_PLAYLIST="${TARGET_PLAYLIST:-}"
    step "compute dedupe order" "$PY" -m seter_shuffle.cli dedupe --library "$DUMP" --out "$ORDER" --order-txt "$ORDER_TXT" || exit 1
    # Skip the apply entirely when there is nothing to remove: a
    # rebuild of an already-clean playlist is pure risk for zero
    # gain, and on a sorted playlist it would also re-exercise the
    # delete/re-add loop for nothing. The order count equals the
    # dump count exactly when the playlist holds no duplicates.
    dump_count="$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d["tracks"]))' "$DUMP")"
    order_count="$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["count"])' "$ORDER")"
    if [ "$order_count" = "$dump_count" ]; then
      log "dedupe done: no duplicate entries in \"$TARGET_PLAYLIST\" ($dump_count songs); nothing was applied"
    else
      log "dedupe: $dump_count entries, $order_count unique songs; applying unique order (first-occurrence order, NOT backup order)"
      apply_order "$TARGET_PLAYLIST" "dedupe"
      log "dedupe done"
    fi
    ;;
esac
