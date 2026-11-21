#!/bin/bash
# run.sh (SeTeR Shuffle, Python experimental core)
#
# Wires the pieces together: AppleScript bridge -> Python core -> bridge.
# The Python core never touches Music; the bridge never decides an
# order. Previews never call the apply script at all.
#
# Usage (from this directory):
#   ./run.sh                       interactive menu (same as ./run.sh menu),
#                                   when stdin is a terminal; with piped
#                                   stdin it prints usage instead, so a
#                                   bare run can never hang waiting for input
#   ./run.sh menu                   interactive Terminal menu (v2.6
#                                   options: shuffle, rediscover,
#                                   dedupe, undo, flow, flowPreview,
#                                   audit); every choice re-invokes
#                                   run.sh, so all gates apply
#   ./run.sh audit                  tag-coverage audit, change nothing
#   ./run.sh flowPreview            print the would-be Flow order, change nothing
#   ./run.sh flow                   build/refresh the Flow target playlist
#                                   (default "SeTeR Flow"; the pool is the
#                                   whole library by default, or one
#                                   playlist — both set in menu Options 8,
#                                   or SETER_FLOW_SOURCE / SETER_FLOW_TARGET)
#   ./run.sh shuffle [playlist] [size]
#                                   shuffle a playlist in place, or the
#                                   whole library into "SeTeR Shuffle";
#                                   size is 100/250/500/1000/all and
#                                   applies only to the whole-library
#                                   shuffle (a sized in-place shuffle
#                                   would drop songs, so it refuses);
#                                   a successful shuffle/flow apply
#                                   stamps the playlist description
#                                   "Last reshuffled: <date/time>"
#                                   best-effort (never fails the apply)
#   ./run.sh rediscover-preview     print Rediscover picks, change nothing
#   ./run.sh rediscover             refresh "SeTeR Rediscover" and record
#                                   history ONLY after a successful apply
#   ./run.sh undo <playlist>        restore a playlist from its last backup
#   ./run.sh dedupe <playlist>      remove duplicate entries from a
#                                   playlist in place (unique songs,
#                                   first occurrence kept); skips
#                                   entirely if it has none.
#                                   IN-PLACE DEDUPE (v3.0.9,
#                                   superseding trial-dedupe v3.0.4
#                                   and presence dedupe v3.0.8,
#                                   both retained but no longer
#                                   called): only the duplicate
#                                   entries are deleted, nothing
#                                   is rebuilt, so success costs
#                                   0 rebuilds and needs no mapping
#                                   at all. A probe still refuses
#                                   on duplicate entries, which is
#                                   why dedupe never probes: it
#                                   does not need to. The probe's
#                                   duplicate refusal is unchanged.
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
#                                   target's builds (fresh for 48
#                                   hours)
#   ./run.sh selfprobe <playlist>   SELF-PROBE (v3.0.2, and auto for
#                                   every build in v3.0.3): measure the
#                                   mapping on the target playlist
#                                   ITSELF, under its own sort.
#                                   Music remembers each playlist's
#                                   own sort, so a mapping measured
#                                   on the target under its own sort
#                                   is, by construction, the mapping
#                                   for that target and sort: no
#                                   throwaway sort to match, no
#                                   mapping transfer possible. The
#                                   probe snapshots the target,
#                                   builds a rotation, restores the
#                                   snapshot under the measured
#                                   mapping, and verifies the
#                                   restore before returning OK.
#                                   A failed restore leaves the
#                                   target holding the rotation
#                                   order, with the snapshot file
#                                   named in the log; recover with
#                                   ./run.sh restore <target>
#                                   <snapshot>. A self-probe on a
#                                   playlist with duplicate entries
#                                   refuses and changes nothing.
#                                   sortprobe with throwaway ==
#                                   target is the same self-probe
#                                   (the sort label is replaced by
#                                   the self-probe label).
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
# use track index. Instead, the mapping is measured either with
# ./run.sh sortprobe on a throwaway set to the SAME sort as the
# target, or (v3.0.2, preferred) with ./run.sh selfprobe on the
# target itself: Music remembers each playlist's own sort, so the
# target's own sort needs no throwaway to imitate it. sort-probe
# builds a rotation on it, reads it back, restores it, and records
# the end-to-end mapping (forward: building X lands list read X;
# reversed: building X lands list read reverse(X)). Since v3.0.3
# every build path (menu, direct shuffle/rediscover/dedupe/flow/
# undo/restore, and the daily run since v3.0.2) AUTO self-probes
# first when no fresh mapping is recorded: a missing or stale
# mapping is refreshed from the target itself, never from a
# throwaway, and a failed probe aborts before any dump or apply.
# Apply and undo read that recorded mapping (fresh for 48 hours,
# else the auto-probe runs again) and pass it to the bridge
# scripts, which build and verify with it
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
# What counts as a duplicate for `dedupe` (and the daily dedupe step):
#   song (default) = same Music track ID, OR same artist + title (and
#                    length, when known), so one song stored as two
#                    library tracks is removed too
#   id             = same Music track ID only (the pre-3.0.6 behaviour)
# Set SETER_DEDUPE_MATCH=id to turn the same-song matching off.
DEDUPE_MATCH="${SETER_DEDUPE_MATCH:-song}"
case "$DEDUPE_MATCH" in
  id|song) ;;
  *) echo "SETER_DEDUPE_MATCH must be 'id' or 'song' (got '$DEDUPE_MATCH')" >&2; exit 2 ;;
esac

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

# Persisted options (menu Options submenu, v3.0.11 exp
# 2026-11-20.3). Three small files under the SeTeRShuffle
# settings dir (${SETER_AI_DIR:-$HOME/Documents/SeTeRShuffle},
# the same dir the AI marker and tag cache already use;
# SETER_AI_DIR is a test hook, never set by a real run):
#   ai-enabled             empty marker: AI tagging for Flow is on
#   split-collabs-enabled  empty marker: "A & B" counts as artist "A"
#   probe-max-age-hours    one number 0-40: the daily run skips a
#                          target's self-probe while its mapping is
#                          younger than N hours (0 = probe every day;
#                          only the daily run reads it)
# The menu writes these files. The Python CLI already reads the
# AI marker itself (ai_enabled_by_environment) and
# SETER_SPLIT_COLLABS (in _settings_from), so the loader below
# turns the split-collabs marker into that env var and the Flow
# playlist files into theirs; the daily run reads the probe-age
# file itself (and its own copy of the Flow loader). An env var
# already set when a script starts wins over the file, so a
# one-off override still works, and the menu says so instead of
# pretending a toggle took effect.
options_dir() {
  printf '%s' "${SETER_AI_DIR:-$HOME/Documents/SeTeRShuffle}"
}

# Effective AI state, mirroring ai_enabled_by_environment: a
# recognized SETER_AI value decides, otherwise the marker file.
options_ai_on() {
  local flag
  flag="$(printf '%s' "${SETER_AI:-}" | tr '[:upper:]' '[:lower:]')"
  case "$flag" in
    1|true|yes|on) return 0 ;;
    0|false|no|off) return 1 ;;
  esac
  [ -f "$(options_dir)/ai-enabled" ]
}

# Whether SETER_AI holds a recognized value (and therefore
# overrides the marker file, so the menu must not pretend a
# toggle changes anything).
options_ai_env_set() {
  local flag
  flag="$(printf '%s' "${SETER_AI:-}" | tr '[:upper:]' '[:lower:]')"
  case "$flag" in
    1|true|yes|on|0|false|no|off) return 0 ;;
    *) return 1 ;;
  esac
}

options_set_ai() {
  local dir
  dir="$(options_dir)"
  if [ "$1" = "on" ]; then
    mkdir -p "$dir" || return 1
    touch "$dir/ai-enabled" || return 1
  else
    rm -f "$dir/ai-enabled"
  fi
  return 0
}

# Effective split-collabs state: an env var set before this
# process started (OPTIONS_SPLIT_ENV_SET, recorded by
# load_persisted_options) decides; otherwise the marker file.
# The loader exports the marker's value into the env, so a
# menu child inherits it, and the toggle below keeps the env
# in step with the marker for the same reason: without that,
# a menu process that exported 1 at startup would hand its
# children a stale 1 after the user toggled the marker off.
options_split_collabs_on() {
  if [ -n "${OPTIONS_SPLIT_ENV_SET:-}" ]; then
    case "$(printf '%s' "${SETER_SPLIT_COLLABS:-}" | tr '[:upper:]' '[:lower:]')" in
      1|true|yes|on) return 0 ;;
      *) return 1 ;;
    esac
  fi
  [ -f "$(options_dir)/split-collabs-enabled" ]
}

options_set_split_collabs() {
  local dir
  dir="$(options_dir)"
  if [ "$1" = "on" ]; then
    mkdir -p "$dir" || return 1
    touch "$dir/split-collabs-enabled" || return 1
    export SETER_SPLIT_COLLABS=1
  else
    rm -f "$dir/split-collabs-enabled"
    export SETER_SPLIT_COLLABS=0
  fi
  return 0
}

# Persisted probe max age in hours (0-40; 0 = probe every
# day), read from the probe-max-age-hours file. Anything
# unreadable or out of range reads as 0, the daily run's own
# default; the menu validates on write, so a bad file can only
# come from a hand edit.
options_probe_max_age() {
  local dir val
  dir="$(options_dir)"
  if [ -f "$dir/probe-max-age-hours" ]; then
    val="$(head -n 1 "$dir/probe-max-age-hours" 2>/dev/null | tr -d ' \t\r\n')"
    case "$val" in
      ''|*[!0-9]*) printf '0'; return 0 ;;
    esac
    if [ "$val" -gt 40 ]; then
      printf '40'
    else
      printf '%s' "$val"
    fi
    return 0
  fi
  printf '0'
}

options_write_probe_max_age() {
  local dir tmp
  dir="$(options_dir)"
  mkdir -p "$dir" || return 1
  tmp="$(mktemp "$dir/.probe-max-age.XXXXXX")" || return 1
  printf '%s\n' "$1" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$dir/probe-max-age-hours" || { rm -f "$tmp"; return 1; }
  return 0
}

# Effective Flow source pool (v3.0.11 exp 2026-11-20.5): the whole
# library, or one named playlist. SETER_FLOW_SOURCE wins when set;
# otherwise the flow-source-playlist file; absent file = library.
# The file holds a playlist name or the literal word "library"
# (any case). A bad file (empty, or only whitespace) reads as
# library, so a hand-edited file can never point Flow at a blank
# playlist name. The value is printed exactly (spaces preserved);
# only a trailing newline / carriage return / spaces are stripped.
options_flow_source() {
  local val lower
  if [ -n "${SETER_FLOW_SOURCE:-}" ]; then
    val="$SETER_FLOW_SOURCE"
  elif [ -f "$(options_dir)/flow-source-playlist" ]; then
    val="$(head -n 1 "$(options_dir)/flow-source-playlist" 2>/dev/null)"
    val="${val%$'\r'}"
    val="$(printf '%s' "$val" | sed 's/[[:space:]]*$//')"
  else
    printf 'library'
    return 0
  fi
  lower="$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]' | tr -d ' \t\r')"
  if [ -z "$lower" ] || [ "$lower" = "library" ]; then
    printf 'library'
  else
    printf '%s' "$val"
  fi
}

# Whether SETER_FLOW_SOURCE was set before this process started
# (recorded by load_persisted_options), and therefore overrides
# the flow-source-playlist file, so the menu must not pretend a
# change takes effect. The loader exports the file's value into
# the env, so the env's presence alone cannot tell the two apart.
options_flow_source_env_set() {
  [ -n "${OPTIONS_FLOW_SOURCE_ENV_SET:-}" ]
}

options_write_flow_source() {
  local dir tmp
  dir="$(options_dir)"
  mkdir -p "$dir" || return 1
  tmp="$(mktemp "$dir/.flow-source-playlist.XXXXXX")" || return 1
  printf '%s\n' "$1" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$dir/flow-source-playlist" || { rm -f "$tmp"; return 1; }
  return 0
}

# Write the Flow source file and keep the in-process env in step
# with it, the same stale-env rule as split collabs: without the
# export, a menu process that exported the old value at startup
# would hand its children the old source after the user changed it.
options_set_flow_source() {
  if options_write_flow_source "$1"; then
    export SETER_FLOW_SOURCE="$1"
    return 0
  fi
  return 1
}

# Effective Flow target playlist (v3.0.11 exp 2026-11-20.5):
# SETER_FLOW_TARGET wins when set; otherwise the
# flow-target-playlist file; absent file = "SeTeR Flow". A bad
# file (empty, or only whitespace) reads as "SeTeR Flow". The
# name is printed exactly (spaces preserved); only a trailing
# newline / carriage return / spaces are stripped.
options_flow_target() {
  local val trimmed
  if [ -n "${SETER_FLOW_TARGET:-}" ]; then
    printf '%s' "$SETER_FLOW_TARGET"
    return 0
  fi
  if [ -f "$(options_dir)/flow-target-playlist" ]; then
    val="$(head -n 1 "$(options_dir)/flow-target-playlist" 2>/dev/null)"
    val="${val%$'\r'}"
    val="$(printf '%s' "$val" | sed 's/[[:space:]]*$//')"
    trimmed="$(printf '%s' "$val" | tr -d ' \t\r')"
    if [ -n "$trimmed" ]; then
      printf '%s' "$val"
      return 0
    fi
  fi
  printf 'SeTeR Flow'
}

# Whether SETER_FLOW_TARGET was set before this process started
# (recorded by load_persisted_options), and therefore overrides
# the flow-target-playlist file.
options_flow_target_env_set() {
  [ -n "${OPTIONS_FLOW_TARGET_ENV_SET:-}" ]
}

options_write_flow_target() {
  local dir tmp
  dir="$(options_dir)"
  mkdir -p "$dir" || return 1
  tmp="$(mktemp "$dir/.flow-target-playlist.XXXXXX")" || return 1
  printf '%s\n' "$1" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$dir/flow-target-playlist" || { rm -f "$tmp"; return 1; }
  return 0
}

# Write the Flow target file and keep the in-process env in step
# with it (same stale-env rule as the source setter above).
options_set_flow_target() {
  if options_write_flow_target "$1"; then
    export SETER_FLOW_TARGET="$1"
    return 0
  fi
  return 1
}

# Turn the persisted split-collabs marker into the env var the
# CLI already reads, unless the env was already set when this
# process started (an explicit env var wins over the file).
# OPTIONS_SPLIT_ENV_SET records which case applied, so the menu
# can tell the user when a toggle would be ignored.
# Flow playlists (v3.0.11 exp 2026-11-20.5) follow the same rule:
# the flow-source-playlist / flow-target-playlist files become
# SETER_FLOW_SOURCE / SETER_FLOW_TARGET unless the env was
# already set, and OPTIONS_FLOW_SOURCE_ENV_SET /
# OPTIONS_FLOW_TARGET_ENV_SET record which case applied. The
# loader exports the effective value either way, so the flow
# branch below can read the env directly and menu children
# inherit the same settings.
load_persisted_options() {
  if [ -n "${SETER_SPLIT_COLLABS:-}" ]; then
    OPTIONS_SPLIT_ENV_SET=1
  elif [ -f "$(options_dir)/split-collabs-enabled" ]; then
    export SETER_SPLIT_COLLABS=1
  fi
  if [ -n "${SETER_FLOW_SOURCE:-}" ]; then
    OPTIONS_FLOW_SOURCE_ENV_SET=1
  else
    export SETER_FLOW_SOURCE="$(options_flow_source)"
  fi
  if [ -n "${SETER_FLOW_TARGET:-}" ]; then
    OPTIONS_FLOW_TARGET_ENV_SET=1
  else
    export SETER_FLOW_TARGET="$(options_flow_target)"
  fi
  return 0
}
load_persisted_options

# Bare ./run.sh opens the interactive menu when stdin is a
# terminal (v3.0.11 exp 2026-11-20.3): double-clicking the
# script or running it with no arguments should land in the
# menu, not print usage. A bare run whose stdin is NOT a
# terminal (piped input, a script, launchd) keeps the old
# behaviour — usage to stderr, exit 2 — so it can never hang
# waiting for input nobody will type.
if [ $# -eq 0 ] && [ -t 0 ]; then
  CMD="menu"
else
  CMD="${1:-}"
fi
case "$CMD" in
  audit|flowPreview|flow|shuffle|rediscover-preview|rediscover|undo|dedupe|restore|probe|probe-keep|sortprobe|selfprobe|menu) ;;
  *)
    echo "usage: $0 {audit|flowPreview|flow|shuffle [playlist] [size]|rediscover-preview|rediscover|undo <playlist>|dedupe <playlist>|restore <playlist> <backup-txt>|probe|probe-keep|sortprobe <throwaway> <target> <sort-label>|selfprobe <playlist>|menu} (run with no arguments in a terminal to open the menu)" >&2
    exit 2
    ;;
esac

# ---- single-run lock (v3.0.11) ------------------------------------
# Two runs touching Music at once (a manual run during the daily job, a
# launchd catch-up after sleep, a double-click) can interleave their
# delete/re-add loops and double a playlist, which is exactly what the
# 2026-10-29 failure looked like. One lock directory per state folder:
# mkdir is atomic, and macOS has no flock(1). The lock records the
# owner's pid and start time; a lock whose owner is dead, or that is
# older than 12 hours, is stale and taken over. A child run.sh started
# by a locked parent (daily.sh, or run.sh's own self-probe) inherits
# SETER_LOCK_HELD=1 and does not lock again.
SETER_LOCK_DIR="${SETER_LOCK_DIR:-$STATE/run.lock.d}"
LOCK_OWNED=0
release_lock() {
  if [ "$LOCK_OWNED" = "1" ] && [ "$(cat "$SETER_LOCK_DIR/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$SETER_LOCK_DIR"
  fi
  LOCK_OWNED=0
}
acquire_lock() {
  local what="$1" pid started age waited tries=0
  [ -n "${SETER_LOCK_HELD:-}" ] && return 0
  while ! mkdir "$SETER_LOCK_DIR" 2>/dev/null; do
    waited=0
    pid="$(cat "$SETER_LOCK_DIR/pid" 2>/dev/null || true)"
    # The owner may be between mkdir and writing its pid: give it a moment.
    while [ -z "$pid" ] && [ "$waited" -lt 3 ] && [ -d "$SETER_LOCK_DIR" ]; do
      sleep 1; waited=$((waited + 1))
      pid="$(cat "$SETER_LOCK_DIR/pid" 2>/dev/null || true)"
    done
    started="$(cat "$SETER_LOCK_DIR/started" 2>/dev/null || echo 0)"
    case "$started" in ''|*[!0-9]*) started=0 ;; esac
    age=$(( $(date +%s) - started ))
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ "$age" -lt 43200 ]; then
      LOCK_HOLDER="pid $pid ($(cat "$SETER_LOCK_DIR/what" 2>/dev/null || echo unknown), started $(date -r "$started" '+%H:%M:%S' 2>/dev/null || echo '?'))"
      return 1
    fi
    tries=$((tries + 1))
    if [ "$tries" -gt 3 ]; then
      LOCK_HOLDER="an unreadable lock at $SETER_LOCK_DIR"
      return 1
    fi
    printf '%s stale run lock removed (%s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${pid:-no pid}" >> "$LOG"
    rm -rf "$SETER_LOCK_DIR"
  done
  printf '%s' "$$" > "$SETER_LOCK_DIR/pid"
  date +%s > "$SETER_LOCK_DIR/started"
  printf '%s' "$what" > "$SETER_LOCK_DIR/what"
  LOCK_OWNED=1
  export SETER_LOCK_HELD=1
  return 0
}


# Read-only commands (and the menu, whose children lock themselves) skip
# the lock; everything that can change a playlist takes it.
case "$CMD" in
  audit|flowPreview|rediscover-preview|menu) ;;
  *)
    if ! acquire_lock "run.sh $CMD"; then
      echo "Another SeTeR run is in progress: $LOCK_HOLDER. Nothing was changed; try again when it finishes." >&2
      printf '%s run.sh %s refused: another run holds the lock (%s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$CMD" "$LOCK_HOLDER" >> "$LOG"
      exit 3
    fi
    ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; release_lock' EXIT
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

# macOS notification, best-effort only: a missing Notification
# Center, a missing osascript, or a denied permission must never
# fail a run that otherwise succeeded or failed on its own terms.
# Double quotes are stripped from the message so a playlist name
# cannot break the osascript argument. Not used inside $(...).
notify() {
  local msg
  msg="$(printf '%s' "$*" | tr -d '"')"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$msg\" with title \"SeTeR Shuffle\"" >/dev/null 2>&1 || log "notification unavailable: $msg"
  else
    log "notification unavailable (no osascript): $msg"
  fi
}

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
# one (older than 48h), and refuse a file whose TARGET field does
# not match, so a build never silently uses a mapping measured for
# a different playlist's sort or a different day. If the target's
# sort may have changed since the probe, the automatic self-probe
# in ensure_mapping_for refreshes it first: a stale mapping is a
# wrong mapping, and a build never proceeds on one.
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
      logerr "GATE FAILED: no per-target sort mapping recorded for '$target' after the automatic self-probe (./run.sh selfprobe '$target'); the pre-.5 shared sort-mapping.txt is ignored since .5 because mappings do not transfer between sorts; see the self-probe error above, no dump or apply ran"
    else
      logerr "GATE FAILED: no sort-matched mapping recorded for '$target' after the automatic self-probe (./run.sh selfprobe '$target'); see the self-probe error above, no dump or apply ran"
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
    logerr "GATE FAILED: recorded mapping for '$target' is not forward or reversed (got '$mapping') after the automatic self-probe (./run.sh selfprobe '$target'); see the self-probe error above, no dump or apply ran"
    return 1
  fi
  if [ "$recorded_target" != "$target" ]; then
    logerr "GATE FAILED: recorded mapping file for '$target' names target '$recorded_target'; mappings do not transfer between targets; the automatic self-probe (./run.sh selfprobe '$target') should have replaced it, see its error above"
    return 1
  fi
  if [ -z "$sort_label" ]; then
    logerr "GATE FAILED: recorded mapping for '$target' has no sort label after the automatic self-probe (./run.sh selfprobe '$target'); see the self-probe error above"
    return 1
  fi
  case "$ts" in ''|*[!0-9]*) logerr "GATE FAILED: recorded mapping for '$target' has no valid timestamp after the automatic self-probe (./run.sh selfprobe '$target'); see the self-probe error above"; return 1;; esac
  if [ $((now - ts)) -gt 172800 ]; then
    logerr "GATE FAILED: recorded mapping for '$target' is older than 48 hours (throwaway '$throwaway', sort '$sort_label') after the automatic self-probe (./run.sh selfprobe '$target'); see the self-probe error above, the probe should have refreshed it"
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
  log "build mapping for '$target': $mapping (throwaway '$throwaway', sort '$sort_label'); if this sort does not match '$target''s sort in Music, stop and re-run ./run.sh selfprobe '$target'"
}

# Print one target's recorded mapping status for the menu (and
# for a human checking before a build). This never authorizes
# anything: the build itself still calls mapping_for_build and
# refuses without a fresh per-target mapping.
mapping_status_for() {
  local target="$1" map_file mapping throwaway sort_label ts now age
  map_file="$(mapping_file_for "$target")"
  if [ ! -f "$map_file" ]; then
    log "mapping status for '$target': none recorded; a build will auto self-probe (./run.sh selfprobe '$target') before refusing"
    return 0
  fi
  mapping="$(grep '^MAPPING: ' "$map_file" | head -n 1 | sed 's/^MAPPING: //')"
  throwaway="$(grep '^THROWAWAY: ' "$map_file" | head -n 1 | sed 's/^THROWAWAY: //')"
  sort_label="$(grep '^SORT: ' "$map_file" | head -n 1 | sed 's/^SORT: //')"
  ts="$(grep '^TIMESTAMP: ' "$map_file" | head -n 1 | sed 's/^TIMESTAMP: //')"
  now="$(date +%s)"
  case "$ts" in ''|*[!0-9]*) log "mapping status for '$target': invalid timestamp; a build will refuse"; return 0;; esac
  age=$((now - ts))
  if [ "$age" -gt 172800 ]; then
    log "mapping status for '$target': STALE ($mapping, throwaway '$throwaway', sort '$sort_label', ${age}s old); a build will auto self-probe (./run.sh selfprobe '$target') before refusing"
  else
    log "mapping status for '$target': $mapping (throwaway '$throwaway', sort '$sort_label', ${age}s old, valid 48 hours)"
  fi
}

# Quiet readiness check used by ensure_mapping_for: 0 only for a
# fresh (<48h), per-target, forward/reversed mapping with a sort
# label and a valid timestamp. It prints nothing: mapping_for_build
# is captured with $(...), and ensure_mapping_for logs its own
# status lines, so a chatty check here would either pollute a
# capture or double-print every gate failure.
mapping_is_ready() {
  local target="$1" map_file mapping recorded_target sort_label ts now age
  map_file="$(mapping_file_for "$target")"
  [ -f "$map_file" ] || return 1
  mapping="$(grep '^MAPPING: ' "$map_file" | head -n 1 | sed 's/^MAPPING: //')"
  recorded_target="$(grep '^TARGET: ' "$map_file" | head -n 1 | sed 's/^TARGET: //')"
  sort_label="$(grep '^SORT: ' "$map_file" | head -n 1 | sed 's/^SORT: //')"
  ts="$(grep '^TIMESTAMP: ' "$map_file" | head -n 1 | sed 's/^TIMESTAMP: //')"
  case "$mapping" in forward|reversed) ;; *) return 1 ;; esac
  [ "$recorded_target" = "$target" ] || return 1
  [ -n "$sort_label" ] || return 1
  case "$ts" in ''|*[!0-9]*) return 1 ;; esac
  now="$(date +%s)"
  age=$((now - ts))
  [ "$age" -le 172800 ]
}

# Automatic self-probe gate (v3.0.3, the fix for the v3.0.2 gap:
# daily.sh auto-probed, but the menu and direct builds still
# refused on a missing mapping and told the user to probe by
# hand). Every build path calls this BEFORE any dump or apply:
# a fresh mapping is reused as-is, with NO re-probe, so a normal
# run costs no extra rebuild; a missing, stale, or otherwise
# unusable mapping triggers ./run.sh selfprobe on the target
# itself, then a re-check. If the mapping is still not ready
# after the probe, the run aborts with the probe error named,
# before any dump or apply, and the menu loops back. Safety
# properties are unchanged: the probe snapshots first, rotates,
# restores under the measured mapping and verifies the restore;
# "other" aborts and deletes the mapping; the duplicate-entry
# refusal is unchanged, so a doubled playlist still fails
# closed here, documented plainly; verify-after still fails
# closed; no other target's mapping is ever borrowed; no fresh
# throwaway probe is ever used. The v3.0.2 restore-failed
# exception still applies inside the probe itself: a mapping
# measured but not restore-verified is recorded so restore can
# run, and the probe exits non-zero, so ensure_mapping_for
# still refuses the build after it.
ensure_mapping_for() {
  local target="$1"
  mapping_status_for "$target"
  if mapping_is_ready "$target"; then
    log "mapping for '$target' is fresh; skipping automatic self-probe"
    return 0
  fi
  log "STEP: automatic self-probe for '$target' (no fresh mapping recorded; probing the target itself under its own sort)"
  if bash "$ROOT/run.sh" selfprobe "$target" 2>&1 | tee -a "$LOG"; then
    if mapping_is_ready "$target"; then
      log "GATE OK: automatic self-probe for '$target' produced a fresh mapping"
      return 0
    fi
    logerr "GATE FAILED: automatic self-probe ./run.sh selfprobe '$target' completed but left no usable mapping; no dump or apply ran for '$target'"
    return 1
  fi
  logerr "GATE FAILED: automatic self-probe ./run.sh selfprobe '$target' failed (see the self-probe error above); no dump or apply ran for '$target'"
  return 1
}

# Legacy pure check (kept for the test harness and for a human
# asking "is this target ready?" without probing): returns 0
# only for a fresh (<48h), per-target, forward/reversed mapping
# with a sort label. The menu and the direct build paths no
# longer use this alone; they use ensure_mapping_for, which
# probes first when this check fails.
mapping_ready_for() {
  local target="$1" map_file mapping sort_label ts now age
  mapping_status_for "$target"
  map_file="$(mapping_file_for "$target")"
  if [ ! -f "$map_file" ]; then
    logerr "GATE FAILED: no per-target sort mapping recorded for '$target'; the automatic self-probe is ./run.sh selfprobe '$target'"
    return 1
  fi
  mapping="$(grep '^MAPPING: ' "$map_file" | head -n 1 | sed 's/^MAPPING: //')"
  sort_label="$(grep '^SORT: ' "$map_file" | head -n 1 | sed 's/^SORT: //')"
  ts="$(grep '^TIMESTAMP: ' "$map_file" | head -n 1 | sed 's/^TIMESTAMP: //')"
  now="$(date +%s)"
  case "$mapping" in
    forward|reversed) ;;
    *) logerr "GATE FAILED: recorded mapping for '$target' is not forward or reversed (got '$mapping'); re-run ./run.sh selfprobe '$target'"; return 1 ;;
  esac
  case "$sort_label" in
    '') logerr "GATE FAILED: recorded mapping for '$target' has no sort label; re-run ./run.sh selfprobe '$target'"; return 1 ;;
  esac
  case "$ts" in
    ''|*[!0-9]*) logerr "GATE FAILED: recorded mapping for '$target' has no valid timestamp; re-run ./run.sh selfprobe '$target'"; return 1 ;;
  esac
  age=$((now - ts))
  if [ "$age" -gt 172800 ]; then
    logerr "GATE FAILED: recorded mapping for '$target' is older than 48 hours; re-run ./run.sh selfprobe '$target' so the mapping matches the target's current sort"
    return 1
  fi
  return 0
}

# It lists Music playlists via bridge/list-playlists.applescript
# into a temp file (never a bash array, and no empty-array
# expansion under set -u: macOS ships bash 3.2, where expanding
# an empty array under set -u is an unbound-variable error),
# numbers them, and lets the user pick a number. Results are
# returned in MENU_PICKED (the picked name, or "" when the user
# typed nothing) and MENU_PICKED_LIBRARY (1 only for shuffle's
# whole-library choice, the old blank-playlist behaviour that
# shuffles the whole library into "SeTeR Shuffle"). 0, an
# invalid pick, an out-of-range number, a failed listing, or
# an empty listing all fall back to typing a name, exactly as
# the old menu did, so a picker failure can never block the
# menu. SETER_MENU_LIST_FILE is a test hook only (never set
# by a real run): when it names an existing file, that file
# is used as the list instead of running osascript, so the
# picker can be tested on a machine with no Music app.
# The picker itself changes nothing in Music and authorizes
# nothing: every caller still runs its own gates afterwards
# (shuffle's ensure_mapping_for, undo's ensure_mapping_for,
# dedupe's own no-precheck path).
menu_pick_playlist() {
  local mode="$1"
  local list_file="" list_ok=0 is_temp=0 count=0 line="" pick="" manual_name="" picked_line=""
  MENU_PICKED=""
  MENU_PICKED_LIBRARY=0
  if [ -n "${SETER_MENU_LIST_FILE:-}" ] && [ -f "${SETER_MENU_LIST_FILE:-}" ]; then
    list_file="$SETER_MENU_LIST_FILE"
    list_ok=1
  else
    list_file="$(mktemp)"
    is_temp=1
    if osascript "$BRIDGE/list-playlists.applescript" > "$list_file" 2>/dev/null && [ -s "$list_file" ]; then
      list_ok=1
    fi
  fi
  if [ "$list_ok" = "1" ] && [ -s "$list_file" ]; then
    printf 'Pick a playlist:\n'
    count=0
    while IFS= read -r line; do
      count=$((count + 1))
      printf '  %s) %s\n' "$count" "$line"
    done < "$list_file"
    if [ "$mode" = "shuffle" ]; then
      printf '  L) Whole library (into SeTeR Shuffle)\n'
    elif [ "$mode" = "flow-source" ]; then
      printf '  L) Whole library (Flow pool)\n'
    fi
    printf '  0) Type a name instead\n'
    printf 'Number: '
    read -r pick || pick=""
    case "$pick" in
      L|l)
        if [ "$mode" = "shuffle" ] || [ "$mode" = "flow-source" ]; then
          MENU_PICKED_LIBRARY=1
        else
          printf 'Playlist: '
          read -r manual_name || manual_name=""
          MENU_PICKED="$manual_name"
        fi
        ;;
      0)
        printf 'Playlist: '
        read -r manual_name || manual_name=""
        MENU_PICKED="$manual_name"
        ;;
      ''|*[!0-9]*)
        echo "not a playlist number; type a name instead."
        printf 'Playlist: '
        read -r manual_name || manual_name=""
        MENU_PICKED="$manual_name"
        ;;
      *)
        if [ "$pick" -ge 1 ] && [ "$pick" -le "$count" ]; then
          picked_line="$(sed -n "${pick}p" "$list_file")"
          MENU_PICKED="$picked_line"
        else
          echo "number $pick is out of range; type a name instead."
          printf 'Playlist: '
          read -r manual_name || manual_name=""
          MENU_PICKED="$manual_name"
        fi
        ;;
    esac
  else
    printf 'Playlist: '
    read -r manual_name || manual_name=""
    MENU_PICKED="$manual_name"
  fi
  if [ "$is_temp" = "1" ]; then
    rm -f "$list_file"
  fi
  return 0
}

# Options submenu (v3.0.11 exp 2026-11-20.3): shows the current
# values, lets the user toggle AI tagging and split collabs and
# set the probe max age, confirms each change, and returns to
# the main menu on 0. Quitting here never quits the menu: the
# function returns, and the main loop prints again. No option
# touches Music or authorizes anything: AI tagging only takes
# effect inside a later Flow compute (which still needs sudo
# fm license once plus ai-selftest first), split collabs only
# changes how the next shuffle/flow/rediscover counts artists,
# and the probe age only changes how often the daily run
# self-probes. Exp 2026-11-20.5 adds the Flow source pool and
# Flow target playlist: the source is the whole library or one
# named playlist, the target is the playlist Flow is applied to,
# and both are picked from the numbered playlist list, so a
# mistyped name can never point Flow at a playlist that does
# not exist. Choosing a source or target only writes its file:
# the next Flow run (menu, direct, or daily) reads it, and the
# daily run and the menu read the same files, so they agree.
menu_options() {
  local choice ai_state split_state probe_age new_age env_note flow_source flow_target flow_source_note flow_target_note picked_lower
  while true; do
    if options_ai_on; then ai_state="ON"; else ai_state="OFF"; fi
    if options_split_collabs_on; then split_state="ON"; else split_state="OFF"; fi
    probe_age="$(options_probe_max_age)"
    env_note=""
    if [ -n "${SETER_PROBE_MAX_AGE_HOURS:-}" ]; then
      env_note=" (SETER_PROBE_MAX_AGE_HOURS=$SETER_PROBE_MAX_AGE_HOURS is set in this shell; the daily run uses that instead)"
    fi
    flow_source="$(options_flow_source)"
    if [ "$flow_source" = "library" ]; then
      flow_source="Whole library"
    fi
    flow_target="$(options_flow_target)"
    flow_source_note=""
    if [ -n "${OPTIONS_FLOW_SOURCE_ENV_SET:-}" ]; then
      flow_source_note=" (SETER_FLOW_SOURCE=$SETER_FLOW_SOURCE is set in this shell; the menu setting is ignored)"
    fi
    flow_target_note=""
    if [ -n "${OPTIONS_FLOW_TARGET_ENV_SET:-}" ]; then
      flow_target_note=" (SETER_FLOW_TARGET=$SETER_FLOW_TARGET is set in this shell; the menu setting is ignored)"
    fi
    printf '\nOptions\n  AI tagging for Flow: %s\n  Split collabs: %s\n  Probe max age: %s hours (0 = probe every day)%s\n  Flow source: %s%s\n  Flow target: %s%s\n  (AI tagging needs sudo fm license once + ai-selftest before Flow uses it.)\n\n  1) Toggle AI tagging\n  2) Toggle split collabs\n  3) Set probe max age (0-40)\n  4) Set Flow source playlist\n  5) Set Flow target playlist\n  0) Back\n' "$ai_state" "$split_state" "$probe_age" "$env_note" "$flow_source" "$flow_source_note" "$flow_target" "$flow_target_note"
    printf 'Choice: '
    read -r choice || return 0
    case "$choice" in
      1)
        if options_ai_env_set; then
          echo "AI tagging is set by SETER_AI=$SETER_AI in the environment; unset it to use the menu setting."
        elif options_ai_on; then
          options_set_ai off && echo "AI tagging is now OFF."
        else
          options_set_ai on && echo "AI tagging is now ON."
        fi
        ;;
      2)
        if [ -n "${OPTIONS_SPLIT_ENV_SET:-}" ]; then
          echo "Split collabs is set by SETER_SPLIT_COLLABS=$SETER_SPLIT_COLLABS in the environment; unset it to use the menu setting."
        elif options_split_collabs_on; then
          options_set_split_collabs off && echo "Split collabs is now OFF."
        else
          options_set_split_collabs on && echo "Split collabs is now ON: \"A & B\" counts as artist \"A\" for spacing and caps."
        fi
        ;;
      3)
        printf 'Probe max age in hours (0-40, 0 = probe every day): '
        read -r new_age || return 0
        case "$new_age" in
          ''|*[!0-9]*)
            echo "not a number 0-40; probe max age unchanged."
            ;;
          *)
            if [ "$new_age" -gt 40 ]; then
              echo "probe max age must be 0-40; probe max age unchanged."
            elif options_write_probe_max_age "$new_age"; then
              echo "Probe max age is now $new_age hours."
            else
              echo "could not save probe max age; unchanged."
            fi
            ;;
        esac
        ;;
      4)
        if [ -n "${OPTIONS_FLOW_SOURCE_ENV_SET:-}" ]; then
          echo "Flow source is set by SETER_FLOW_SOURCE=$SETER_FLOW_SOURCE in the environment; unset it to use the menu setting."
        else
          menu_pick_playlist flow-source
          if [ "$MENU_PICKED_LIBRARY" = "1" ]; then
            if options_set_flow_source library; then
              echo "Flow source is now the whole library."
            else
              echo "could not save Flow source; unchanged."
            fi
          elif [ -n "$MENU_PICKED" ]; then
            picked_lower="$(printf '%s' "$MENU_PICKED" | tr '[:upper:]' '[:lower:]' | tr -d ' \t\r')"
            if [ "$picked_lower" = "library" ]; then
              if options_set_flow_source library; then
                echo "Flow source is now the whole library."
              else
                echo "could not save Flow source; unchanged."
              fi
            elif options_set_flow_source "$MENU_PICKED"; then
              echo "Flow source is now \"$MENU_PICKED\"."
            else
              echo "could not save Flow source; unchanged."
            fi
          else
            echo "empty name; Flow source unchanged."
          fi
        fi
        ;;
      5)
        if [ -n "${OPTIONS_FLOW_TARGET_ENV_SET:-}" ]; then
          echo "Flow target is set by SETER_FLOW_TARGET=$SETER_FLOW_TARGET in the environment; unset it to use the menu setting."
        else
          menu_pick_playlist flow-target
          if [ -n "$MENU_PICKED" ]; then
            if options_set_flow_target "$MENU_PICKED"; then
              echo "Flow target is now \"$MENU_PICKED\"."
            else
              echo "could not save Flow target; unchanged."
            fi
          else
            echo "empty name; Flow target unchanged."
          fi
        fi
        ;;
      0|q|quit)
        return 0
        ;;
      *)
        echo "unknown choice: $choice"
        ;;
    esac
  done
}

# Interactive menu (Terminal only, matching v2.6's interactive
# options; there is no .app bundle in this build). Choices
# 1, 3, and 4 pick a playlist from a numbered list
# (menu_pick_playlist, v3.0.10) instead of requiring a typed
# name, with 0 to type a name and a whole-library choice for
# shuffle. Every choice
# re-invokes run.sh as a fresh process, so every gate in the
# non-interactive paths applies unchanged: a build still refuses
# without a fresh per-target mapping, still validates its order,
# still snapshots and verifies. The menu pre-checks the mapping
# with ensure_mapping_for before invoking any build: a fresh
# mapping is reused with no re-probe, and a missing or stale
# mapping triggers an automatic self-probe of the target itself
# before any dump, not after it. A failed probe loops the menu
# back with the probe error visible; the menu never picks a
# mapping, never borrows another target's mapping, and never
# overrides a refusal. Playlist names may contain spaces; size is
# the documented 100/250/500/1000/all choice, blank for all.
if [ "$CMD" = "menu" ]; then
  while true; do
    printf '\nSeTeR Shuffle\n  1) Shuffle a playlist\n  2) Rediscover\n  3) Remove duplicates (dedupe)\n  4) Undo last shuffle\n  5) Flow\n  6) Flow preview\n  7) Audit\n  8) Options\n  0) Quit\n'
    printf 'Choice: '
    read -r choice || exit 0
    case "$choice" in
      1)
        menu_pick_playlist shuffle
        if [ "$MENU_PICKED_LIBRARY" = "1" ] || [ -z "$MENU_PICKED" ]; then
          pl=""
          menu_target="SeTeR Shuffle"
        else
          pl="$MENU_PICKED"
          menu_target="$MENU_PICKED"
        fi
        ensure_mapping_for "$menu_target" || continue
        printf 'Size (100/250/500/1000/all, blank for all): '
        read -r sz || exit 0
        # No array here, for the same bash 3.2 reason as the
        # shuffle-size fix below: an empty array under set -u
        # is an unbound-variable error on macOS /bin/bash, and
        # a blank playlist and a blank size are both legal.
        if [ -n "$pl" ] && [ -n "$sz" ]; then
          bash "$ROOT/run.sh" shuffle "$pl" "$sz" || notify "SeTeR Shuffle: shuffle failed"
        elif [ -n "$pl" ]; then
          bash "$ROOT/run.sh" shuffle "$pl" || notify "SeTeR Shuffle: shuffle failed"
        elif [ -n "$sz" ]; then
          bash "$ROOT/run.sh" shuffle "$sz" || notify "SeTeR Shuffle: shuffle failed"
        else
          bash "$ROOT/run.sh" shuffle || notify "SeTeR Shuffle: shuffle failed"
        fi
        ;;
      2)
        ensure_mapping_for "SeTeR Rediscover" || continue
        bash "$ROOT/run.sh" rediscover || notify "SeTeR Shuffle: rediscover failed"
        ;;
      3)
        menu_pick_playlist dedupe
        pl="$MENU_PICKED"
        [ -n "$pl" ] || { echo "dedupe needs a playlist name."; continue; }
        # No pre-check here (v3.0.4): dedupe handles its own
        # mapping, because a doubled playlist fails the
        # self-probe on duplicate entries and would deadlock the
        # menu otherwise. A fresh mapping is used directly;
        # otherwise the trial path tries forward then reversed.
        bash "$ROOT/run.sh" dedupe "$pl" || notify "SeTeR Shuffle: dedupe failed"
        ;;
      4)
        menu_pick_playlist undo
        pl="$MENU_PICKED"
        [ -n "$pl" ] || { echo "undo needs a playlist name."; continue; }
        ensure_mapping_for "$pl" || continue
        bash "$ROOT/run.sh" undo "$pl" || notify "SeTeR Shuffle: undo failed"
        ;;
      5)
        ensure_mapping_for "$(options_flow_target)" || continue
        bash "$ROOT/run.sh" flow || notify "SeTeR Shuffle: flow failed"
        ;;
      6)
        bash "$ROOT/run.sh" flowPreview || notify "SeTeR Shuffle: flow preview failed"
        ;;
      7)
        bash "$ROOT/run.sh" audit || notify "SeTeR Shuffle: audit failed"
        ;;
      8)
        menu_options
        ;;
      0|q|quit)
        exit 0
        ;;
      *)
        echo "unknown choice: $choice"
        ;;
    esac
  done
fi

# Sort-probe command: measure the mapping FOR ONE TARGET. Since .5
# the target and the sort label are required arguments, and the
# mapping is recorded per-target (mapping_file_for): a mapping
# measured for target X can never authorize a build on target Y.
# Two forms, same probe script, same safety:
#   * sortprobe <throwaway> <target> <sort-label>: the user MUST
#     set the throwaway's sort in Music to the target's sort before
#     running this; run.sh cannot set or verify a playlist's UI
#     sort, so a throwaway with the wrong sort measures the wrong
#     mapping, and the STEP line below records exactly what was
#     declared. Worked example of why this matters (2026-10-29,
#     mode 35): the main playlist sorts Playlist Order descending
#     (mapping reversed), while a brand-new "SeTeR Flow" playlist
#     sorts default/manual (mapping forward); reusing the main
#     playlist's mapping for Flow landed backwards and verify
#     correctly refused it. Flow therefore needs its OWN
#     sortprobe, on a throwaway set to SeTeR Flow's sort, before
#     any Flow build, even when a main-playlist mapping already
#     exists.
#   * selfprobe <target> (v3.0.2, preferred): the probe runs on
#     the target itself, under the target's own sort, which Music
#     remembers per playlist. There is no throwaway sort to match
#     and no mapping transfer is possible: the measured mapping is
#     the target's own. sortprobe with throwaway == target is the
#     same self-probe; its sort label is replaced by the
#     self-probe label below, and mapping_for_build accepts that
#     label like any other non-empty sort label (it is the
#     THROWAWAY field, equal to the target, that marks it).
# In both forms the probe snapshots first, builds a rotation,
# restores the snapshot under the measured mapping, and verifies
# the restore before returning OK. The duplicate-entry refusal
# is unchanged: a probe on a playlist with duplicate entries
# refuses and changes nothing, so a doubled playlist cannot be
# probed (self or throwaway) until it is trial-deduped
# (v3.0.4: dedupe verifies its own mapping, it does not
# probe); the refusal is NOT weakened to work around
# that deadlock.
# Failure handling, and the ONE exception to "a failed probe
# deletes the mapping": a probe that measured forward/reversed
# but could not verify its own restore leaves the probed
# playlist holding the rotation order. Deleting the mapping
# there would block the only recovery path (./run.sh restore
# needs a fresh mapping), so that case RECORDS the measured
# mapping and logs a loud warning naming the snapshot, and the
# caller (daily.sh included) still exits non-zero: no build
# runs until the playlist is restored from the snapshot and a
# clean probe passes. Every other failure (other mapping,
# duplicate refusal, unreadable playlist, pre-build failure)
# deletes the per-target mapping as before, because the sort
# is then unknown and a stale mapping must never authorize a
# build. Other targets' mappings are untouched in all cases.
if [ "$CMD" = "sortprobe" ] || [ "$CMD" = "selfprobe" ]; then
  SELF_PROBE_LABEL="self-probe: target's own sort"
  if [ "$CMD" = "selfprobe" ]; then
    THROWAWAY="${2:-}"
    PROBE_TARGET="${2:-}"
    PROBE_SORT="$SELF_PROBE_LABEL"
    if [ -z "$THROWAWAY" ]; then
      echo "usage: $0 selfprobe <playlist>" >&2
      echo "  example: $0 selfprobe 'My New Sandwich Recipe'" >&2
      exit 2
    fi
  else
    THROWAWAY="${2:-}"
    PROBE_TARGET="${3:-}"
    PROBE_SORT="${4:-}"
    if [ -z "$THROWAWAY" ] || [ -z "$PROBE_TARGET" ] || [ -z "$PROBE_SORT" ]; then
      echo "usage: $0 sortprobe <throwaway-playlist> <target-playlist> <sort-label>" >&2
      echo "  example: $0 sortprobe 'Throwaway' 'My New Sandwich Recipe' 'Playlist Order descending'" >&2
      echo "  the throwaway must be set in Music to the target's sort BEFORE running; the sort label is your declaration of that sort, e.g. 'Playlist Order descending', 'Playlist Order ascending', or 'Manual (default)'" >&2
      echo "  or run: $0 selfprobe 'My New Sandwich Recipe' (probe the target itself under its own sort)" >&2
      exit 2
    fi
    if [ "$THROWAWAY" = "$PROBE_TARGET" ]; then
      PROBE_SORT="$SELF_PROBE_LABEL"
    fi
  fi
  SNAPSHOT="$STATE/sort-probe-snapshot.txt"
  MAP_FILE="$(mapping_file_for "$PROBE_TARGET")"
  if [ "$THROWAWAY" = "$PROBE_TARGET" ]; then
    log "STEP: self-probe mapping on target '$PROBE_TARGET' itself (its own sort, as Music remembers it; snapshot at $SNAPSHOT; the probe restores the target to its snapshot and verifies before returning OK)"
  else
    log "STEP: sort-probe mapping on throwaway '$THROWAWAY' for target '$PROBE_TARGET' (declared sort: '$PROBE_SORT'; set the throwaway to this sort in Music before running)"
  fi
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
      log "GATE OK: sort-probe mapping $mapping recorded for target '$PROBE_TARGET' (valid 48 hours; throwaway '$THROWAWAY', sort '$PROBE_SORT')"
      if [ "$THROWAWAY" = "$PROBE_TARGET" ]; then
        log "self-probe done; target '$PROBE_TARGET' restored to its snapshot and verified; then run the build for '$PROBE_TARGET'"
      else
        log "sortprobe done; throwaway restored to its snapshot; verify it in Music if you want, then run the build for '$PROBE_TARGET'"
      fi
      exit 0
    fi
  fi
  # Measured-mapping-but-restore-failed exception (see the header
  # above): the probe output names a forward/reversed mapping and
  # a restore that could not be verified. Record that mapping so
  # ./run.sh restore can run, warn loudly, and still exit
  # non-zero so no build follows a half-restored probe.
  if grep -q 'MAPPING: reversed' "$WORK/sortprobe.out" 2>/dev/null || grep -q 'MAPPING: forward' "$WORK/sortprobe.out" 2>/dev/null; then
    if grep -qi 'restore.*could not be verified\|restore to its snapshot could not be verified' "$WORK/sortprobe.out" 2>/dev/null; then
      if grep -q 'MAPPING: reversed' "$WORK/sortprobe.out" 2>/dev/null; then mapping="reversed"; else mapping="forward"; fi
      {
        printf 'MAPPING: %s\n' "$mapping"
        printf 'THROWAWAY: %s\n' "$THROWAWAY"
        printf 'TARGET: %s\n' "$PROBE_TARGET"
        printf 'SORT: %s\n' "$PROBE_SORT"
        printf 'TIMESTAMP: %s\n' "$(date +%s)"
      } > "$MAP_FILE.tmp"
      mv -f "$MAP_FILE.tmp" "$MAP_FILE"
      log "GATE FAILED: sort-probe measured mapping $mapping for target '$PROBE_TARGET' but could not verify restoring it to its snapshot; the probed playlist may still hold the rotation order. Its snapshot is at $SNAPSHOT: restore it first with ./run.sh restore '$PROBE_TARGET' '$SNAPSHOT', then re-run the probe. No build will run until a clean probe passes."
      notify "SeTeR Shuffle: sortprobe restore failed for $PROBE_TARGET"
      exit 1
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
  if [ "$THROWAWAY" = "$PROBE_TARGET" ]; then
    log "self-probe on '$PROBE_TARGET': if the probe returned 'other', the target's own sort is not one the bridge can build into, so no build will run for it until its sort changes and a clean self-probe passes; if it refused on duplicate entries, the target is unchanged, dedupe it first. Snapshot (when written) is at $SNAPSHOT"
  else
    log "check the throwaway '$THROWAWAY' in Music: if the probe could not restore it, its snapshot is at $SNAPSHOT"
  fi
  notify "SeTeR Shuffle: sortprobe failed for $PROBE_TARGET"
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
  ensure_mapping_for "$PLAYLIST" || exit 1
  MAPPING="$(mapping_for_build "$PLAYLIST")" || exit 1
  mapping_info_for "$PLAYLIST"
  log "undo $PLAYLIST from $BACKUP (mapping $MAPPING; pre-undo snapshot will be saved at $BACKUP.pre-undo)"
  step "undo $PLAYLIST" osascript "$BRIDGE/undo.applescript" "$PLAYLIST" "$BACKUP" "$MAPPING" || { notify "SeTeR Shuffle: undo failed for $PLAYLIST"; exit 1; }
  log "undo done"
  notify "SeTeR Shuffle: undo done for $PLAYLIST"
  exit 0
fi

# Restore from an explicit backup file, through the same gate as
# undo: a freshness-checked sort-matched mapping, and a backup
# file that must exist before anything is deleted. This is the
# only supported way to call restore-original.applescript: a direct
# osascript call to it bypasses the freshness check (the script
# cannot know when the mapping was measured), so direct calls are
# expert-only and must be given a mapping measured within 48 hours
# on a throwaway carrying the target's sort, or by a self-probe
# on the target itself.
if [ "$CMD" = "restore" ]; then
  PLAYLIST="${2:-}"
  BACKUP="${3:-}"
  [ -n "$PLAYLIST" ] && [ -n "$BACKUP" ] || { echo "usage: $0 restore <playlist> <backup-txt>" >&2; exit 2; }
  if [ ! -f "$BACKUP" ]; then
    log "GATE FAILED: backup file $BACKUP does not exist; restore refuses, playlist untouched"
    exit 1
  fi
  ensure_mapping_for "$PLAYLIST" || exit 1
  MAPPING="$(mapping_for_build "$PLAYLIST")" || exit 1
  mapping_info_for "$PLAYLIST"
  log "restore $PLAYLIST from $BACKUP (mapping $MAPPING; pre-fix snapshot will be saved at $BACKUP.fix-snapshot)"
  step "restore $PLAYLIST" osascript "$BRIDGE/restore-original.applescript" "$PLAYLIST" "$BACKUP" "$MAPPING" || { notify "SeTeR Shuffle: restore failed for $PLAYLIST"; exit 1; }
  log "restore done"
  notify "SeTeR Shuffle: restore done for $PLAYLIST"
  exit 0
fi

# Shuffle size (v2.6 library-shuffle size choice, wired into
# run.sh): ./run.sh shuffle [playlist] [size], or
# ./run.sh shuffle [size] for a whole-library shuffle into
# "SeTeR Shuffle", or SETER_SHUFFLE_SIZE. Size is one of
# 100/250/500/1000/all; "all" and blank both mean the whole
# library/playlist, which is also the daily default. An invalid
# size refuses before any dump, so a typo cannot shuffle the
# wrong slice. The CLI --size caps the shuffled output (first N
# of the Fisher-Yates order, then artist-spaced), matching v2.6.
SHUFFLE_PLAYLIST=""
SHUFFLE_SIZE="${SETER_SHUFFLE_SIZE:-}"
if [ "$CMD" = "shuffle" ]; then
  if [ -n "${2:-}" ]; then
    case "$2" in
      100|250|500|1000|all) SHUFFLE_SIZE="$2" ;;
      *) SHUFFLE_PLAYLIST="$2" ;;
    esac
  fi
  if [ -n "${3:-}" ]; then
    case "$3" in
      100|250|500|1000|all) SHUFFLE_SIZE="$3" ;;
      *) echo "usage: $0 shuffle [playlist] [size: 100|250|500|1000|all]" >&2; exit 2 ;;
    esac
  fi
  case "$SHUFFLE_SIZE" in
    ""|all|100|250|500|1000) ;;
    *) echo "invalid shuffle size '$SHUFFLE_SIZE' (use 100, 250, 500, 1000, or all)" >&2; exit 2 ;;
  esac
  # Size applies ONLY to a whole-library shuffle into "SeTeR
  # Shuffle" (a generated playlist). An in-place shuffle must
  # reorder the whole playlist, never drop songs from it, so a
  # sized in-place shuffle refuses here, before any dump.
  if [ -n "$SHUFFLE_PLAYLIST" ] && [ -n "$SHUFFLE_SIZE" ] && [ "$SHUFFLE_SIZE" != "all" ]; then
    echo "shuffle size applies only to a whole-library shuffle (./run.sh shuffle [size]); an in-place playlist shuffle always reorders the whole playlist" >&2
    exit 2
  fi
fi

# Automatic self-probe before any dump (v3.0.3): the build
# target for this command gets ensure_mapping_for first, so a
# missing or stale mapping is refreshed from the target itself
# and a failed probe aborts before the dump, the compute, or
# the apply. Audit and preview commands never reach this block
# with a build target, so they probe nothing. apply_order still
# re-checks with mapping_for_build as its final gate.
# Dedupe is EXEMPT from this block (v3.0.4): a doubled playlist
# fails the self-probe on duplicate entries, so probing first
# would deadlock dedupe exactly as it did on 2026-10-29. The
# dedupe case below handles its own mapping: a fresh mapping
# is used directly, otherwise dedupe_trial_apply() tries
# forward then reversed with verify-after as the oracle.
case "$CMD" in
  shuffle) ensure_mapping_for "${SHUFFLE_PLAYLIST:-SeTeR Shuffle}" || exit 1 ;;
  dedupe) [ -n "${2:-}" ] || { echo "usage: $0 dedupe <playlist>" >&2; exit 2; } ;;
  flow) ensure_mapping_for "$(options_flow_target)" || exit 1 ;;
  rediscover) ensure_mapping_for "SeTeR Rediscover" || exit 1 ;;
esac

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
elif [ "$CMD" = "shuffle" ] && [ -n "$SHUFFLE_PLAYLIST" ]; then
  SOURCE_PLAYLIST="$SHUFFLE_PLAYLIST"
  TARGET_PLAYLIST="$SHUFFLE_PLAYLIST"
  step "dump playlist $SOURCE_PLAYLIST" osascript "$BRIDGE/dump-library.applescript" "$DUMP" "$SOURCE_PLAYLIST" || exit 1
elif { [ "$CMD" = "flow" ] || [ "$CMD" = "flowPreview" ]; } && [ "$(options_flow_source)" != "library" ]; then
  # Flow from one playlist (v3.0.11 exp 2026-11-20.5): the pool is
  # that playlist's dump, and the target is the configured Flow
  # target, so the same settings the menu shows are the ones this
  # run uses. The source needs no probe (a dump is a read); the
  # target's mapping was checked above, before any dump.
  SOURCE_PLAYLIST="$(options_flow_source)"
  TARGET_PLAYLIST="$(options_flow_target)"
  step "dump playlist $SOURCE_PLAYLIST for flow" osascript "$BRIDGE/dump-library.applescript" "$DUMP" "$SOURCE_PLAYLIST" || exit 1
else
  step "dump library" osascript "$BRIDGE/dump-library.applescript" "$DUMP" || exit 1
fi

export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

# Validate an order, then apply it, with restore-on-failure. The
# bridge also validates and verifies on its own side; this function
# is the runner's half: catch a bad order before Music is touched,
# and recover if the apply step itself fails after changes start.
# apply_order() is the normal entry point: it reads the recorded
# sort-matched mapping first (a missing or stale mapping costs
# nothing, and an unmapped apply must never run), then calls
# apply_order_mapped(). Trial-dedupe (v3.0.4) calls
# apply_order_mapped() directly with an explicit trial mapping,
# because its mapping is what is being tested, not what is
# recorded. Return codes from apply_order_mapped(): 0 on a
# verified apply; 1 on an apply failure whose playlist was
# restored (or never changed), so a trial caller may safely try
# the other mapping; 2 on an apply failure whose restore failed
# under BOTH mappings inside apply-order and inside undo
# (v3.0.5, mode 41) and left the playlist possibly partial, so
# a trial caller must NOT try the other mapping on top of a
# partial state. A restore failure no longer means "the one
# mapping tried was wrong": both were tried, each verified
# against the snapshot, before code 2 is returned. Normal
# callers run under set -e, so any non-zero return stops the
# run, exactly as the old exit 1 did.
# APPLY_LAST_RUN_BACKUP and APPLY_RESTORE_FAILED are globals
# set here for trial callers: the per-run snapshot to name in a
# hard error, and whether the last attempt's restore failed
# critically (partial), as opposed to merely failing to verify.
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
# previous file. The per-run filename also carries $RANDOM, so
# two trial attempts inside the same second can never share a
# snapshot file and overwrite each other's restore point.
apply_order() {
  local target="$1" mode="$2" build_mapping
  build_mapping="$(mapping_for_build "$target")" || exit 1
  mapping_info_for "$target"
  apply_order_mapped "$target" "$mode" "$build_mapping" || exit 1
}

apply_order_mapped() {
  local target="$1" mode="$2" build_mapping="$3" backup run_backup lib_songs allow_dupes
  local -a apply_args
  backup="$(backup_path_for "$target")"
  run_backup="${backup%.txt}.run-$(date +%Y%m%d-%H%M%S)-$$-$RANDOM.txt"
  APPLY_LAST_RUN_BACKUP="$run_backup"
  APPLY_RESTORE_FAILED=0
  # A size-capped whole-library shuffle is a subset by design
  # (N songs into the generated "SeTeR Shuffle" playlist), so it
  # validates under "shuffle-size" (presence/multiplicity only),
  # not "shuffle" (exact multiset equality, which a subset would
  # rightly fail). Every other mode keeps its exact rule.
  validate_mode="$mode"
  if [ "$mode" = "shuffle" ] && [ -z "${SOURCE_PLAYLIST:-}" ] && [ -n "${SHUFFLE_SIZE:-}" ] && [ "$SHUFFLE_SIZE" != "all" ]; then
    validate_mode="shuffle-size"
  fi
  step "validate order ($mode) for $target" "$PY" -m seter_shuffle.cli validate-order --library "$DUMP" --order-txt "$ORDER_TXT" --order-json "$ORDER" --mode "$validate_mode" --dedupe-match "$DEDUPE_MATCH" || return 1
  log "GATE: order validated for $target"
  # Duplicate allowance: "1" only for a one-playlist shuffle whose
  # dump itself repeats an ID (duplicate playlist entries, preserved
  # as positions). Every other mode refuses duplicate order IDs.
  # Dedupe forces "0" even though its dump repeats IDs: the dedupe
  # order itself is unique by construction, and allowing duplicates
  # there would weaken the bridge's second check for no reason.
  # Flow forces "0" for the same reason (v3.0.11 exp 2026-11-20.5):
  # a flow order is unique by construction (the CLI loads the pool
  # with duplicates refused and emits each song once), so a doubled
  # source playlist must not loosen the bridge's check. The CLI
  # already fails closed on a doubled pool dump before any apply,
  # so this is the second half of the same gate, not the only one.
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
    lib_songs="$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d["tracks"]))' "$DUMP")" || { log "GATE FAILED: could not count songs in dump"; return 1; }
  fi
  if [ "$mode" = "dedupe" ] || [ "$mode" = "flow" ]; then
    allow_dupes="0"
  fi
  # Description stamp (v2.6 "Last reshuffled" parity): for
  # shuffle, flow, and rediscover, only as the 7th bridge
  # argument, and only after verification passes inside
  # apply-order. The bridge stamps "Last reshuffled: <Mac
  # local date/time at the verified apply>", best-effort: if
  # Music's scripting does not expose a settable playlist
  # description, the stamp step logs skipped and the
  # already-verified apply still succeeds. Undo and restore
  # never stamp (they do not call this function), and dedupe
  # does not stamp, because dedupe is not a reshuffle or a
  # refresh. Rediscover stamps from v3.0.9: a daily refresh
  # should leave its own last-refresh time on its description,
  # not a stale manual-run time.
  stamp_flag="0"
  if [ "$mode" = "shuffle" ] || [ "$mode" = "flow" ] || [ "$mode" = "rediscover" ]; then
    stamp_flag="1"
  fi
  # Verify mode (v3.0.8): dedupe verifies presence only, per
  # Spencer's 2026-10-30 answer that dedupe need not keep the
  # original order. Every other mode verifies exact order.
  verify_mode="exact"
  if [ "$mode" = "dedupe" ]; then
    verify_mode="presence"
  fi
  if [ -n "$lib_songs" ]; then
    apply_args=("$target" "$ORDER_TXT" "$run_backup" "$build_mapping" "$allow_dupes" "$lib_songs" "$stamp_flag" "$verify_mode")
  else
    apply_args=("$target" "$ORDER_TXT" "$run_backup" "$build_mapping" "$allow_dupes" "" "$stamp_flag" "$verify_mode")
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
    notify "SeTeR Shuffle: $target applied ($mode)"
  else
    log "GATE FAILED: apply failed for $target"
    notify "SeTeR Shuffle: apply failed for $target ($mode)"
    # Skip the redundant undo restore (v3.0.7, 2026-10-29 21:01
    # trial-dedupe): apply-order's own error message says whether
    # its internal restore succeeded ("playlist restored from
    # backup") or failed under both mappings ("CRITICAL"). When
    # it already restored, the playlist is back at the per-run
    # snapshot, and running undo on top of it only rebuilds the
    # same snapshot again, under the wrong mapping first, then
    # under the opposite one: 3 extra rebuilds for no change,
    # and undo's "restored to pre-undo state" exit then looks
    # like a critical restore failure and stops a trial-dedupe
    # before it ever tries the other mapping. Only lines since
    # this apply's STEP line count, so an older run cannot
    # false-positive here. A CRITICAL apply still falls through
    # to undo below, because then the playlist is not known to
    # be back at the snapshot.
    apply_step_line="$(grep -n "STEP: apply order to $target" "$LOG" | tail -n 1 | cut -d: -f1)"
    if [ -n "$apply_step_line" ] && tail -n +"$apply_step_line" "$LOG" | grep -q "restored from backup" && ! tail -n +"$apply_step_line" "$LOG" | grep -q "CRITICAL"; then
      log "apply already restored the playlist from its per-run snapshot at $run_backup; skipping the redundant undo restore (v3.0.7); main backup at $backup was NOT overwritten by this failed run"
      return 1
    fi
    if [ -f "$run_backup" ]; then
      log "per-run snapshot exists at $run_backup; attempting restore via undo (undo itself tries both mappings, v3.0.5); main backup at $backup was NOT overwritten by this failed run"
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
          APPLY_RESTORE_FAILED=1
        fi
      fi
    else
      log "no per-run snapshot was written, so the apply failed before any playlist change; playlist untouched and main backup at $backup untouched"
    fi
    if [ "${APPLY_RESTORE_FAILED:-0}" = "1" ]; then
      return 2
    fi
    return 1
  fi
  return 0
}

# Record a mapping verified by a trial-dedupe apply (v3.0.4).
# This is NOT a probe result: no rotation was built, and the
# mapping was proven by verify-after on the actual deduped
# order. It is recorded in the same per-target file format so
# the next build can reuse it directly, with a SORT label that
# says exactly how it was obtained. Trial callers record ONLY
# on success; a failed trial records nothing, so a total trial
# failure leaves no mapping behind for a later build to trust.
record_trial_mapping() {
  local target="$1" mapping="$2" map_file
  map_file="$(mapping_file_for "$target")"
  {
    printf 'MAPPING: %s\n' "$mapping"
    printf 'THROWAWAY: %s\n' "$target"
    printf 'TARGET: %s\n' "$target"
    printf 'SORT: trial-dedupe: verified by dedupe apply\n'
    printf 'TIMESTAMP: %s\n' "$(date +%s)"
  } > "$map_file.tmp"
  mv -f "$map_file.tmp" "$map_file"
  log "GATE: trial-dedupe verified mapping $mapping recorded for target '$target' (verified by dedupe apply, not by a rotation probe)"
}

# Trial-dedupe (v3.0.4): the dedupe path when no fresh mapping
# is recorded. The rotation probe cannot help here: it refuses
# on duplicate entries, and a doubled playlist is exactly a
# playlist with duplicate entries. So dedupe tries its known
# desired order (first occurrence of each song, computed before
# this function runs) under mapping forward, verifies the list
# read against it inside the apply, and on failure restores
# from the per-run snapshot and tries reversed. The first
# mapping that verifies wins and is recorded (see
# record_trial_mapping). If neither verifies (for example an
# "other" sort like Title ascending, where neither forward nor
# reversed can land the desired order), the playlist is left
# at its pre-dedupe order, no mapping is recorded, and this
# returns 1. If an attempt's restore fails under BOTH mappings
# (v3.0.5: apply-order's internal restore and undo's restore
# each try the trial mapping first, then the opposite, each
# verified against the snapshot), the playlist may be partial,
# this returns 2 immediately, and the trial does NOT try the
# other mapping on top of a partial state. A restore failure
# after v3.0.5 therefore means neither mapping could return
# the playlist to its snapshot, not merely that the trial
# mapping was wrong: the opposite mapping was already tried
# for the restore before the trial stopped.
# The probe is never involved: this function must not be
# generalized into a probe bypass, because the probe's job is
# to classify a sort from a rotation without changing the
# target's intended order, while dedupe's job is to change
# the target to a known order and check the result.
dedupe_trial_apply() {
  local target="$1" trial_mapping
  for trial_mapping in forward reversed; do
    log "STEP: trial-dedupe apply for '$target' with mapping $trial_mapping (verify-after on the deduped order is the mapping oracle)"
    APPLY_RESTORE_FAILED=0
    if apply_order_mapped "$target" "dedupe" "$trial_mapping"; then
      record_trial_mapping "$target" "$trial_mapping"
      log "dedupe trial succeeded with mapping $trial_mapping; playlist deduped and mapping recorded"
      return 0
    fi
    if [ "${APPLY_RESTORE_FAILED:-0}" = "1" ]; then
      log "CRITICAL: trial-dedupe apply with mapping $trial_mapping failed AND its restore failed under both mappings; playlist may be partial; snapshot at $APPLY_LAST_RUN_BACKUP; not trying the other mapping"
      return 2
    fi
    log "trial-dedupe apply with mapping $trial_mapping did not verify; playlist restored to its pre-dedupe order; trying the other mapping"
  done
  log "GATE FAILED: trial-dedupe for '$target': neither forward nor reversed mapping verified; playlist restored to its pre-dedupe order; change the sort to Playlist Order and re-run dedupe; no mapping was recorded"
  return 1
}

# In-place dedupe (v3.0.9, superseding presence dedupe v3.0.8
# before v3.0.8 was ever published). Spencer's cap, 2026-10-30:
# dedupe must rebuild his playlist 1-2 times max. A rebuild is
# the wrong tool for dedupe at all: deleting only the duplicate
# entries in place costs 0 rebuilds on success, needs no
# mapping, no probe, and no trial, because nothing is re-added
# in any order. The bridge script snapshots (verified, atomic)
# before deleting, deletes duplicate positions in descending
# order, verifies presence only, and on failure restores from
# the snapshot trying both mappings, exactly like apply-order.
# Only that restore is a rebuild, and only on a failed run.
# This function mirrors apply_order_mapped's backup chain:
# the per-run snapshot becomes the main backup only after a
# verified success, with the previous main backup kept as .prev.
# Return codes: 0 on success; 1 on a failure whose playlist
# was restored (or never changed); 2 on a CRITICAL failure
# whose restore failed under both mappings.
dedupe_in_place() {
  local target="$1" backup run_backup delete_txt
  backup="$(backup_path_for "$target")"
  run_backup="${backup%.txt}.run-$(date +%Y%m%d-%H%M%S)-$$-$RANDOM.txt"
  delete_txt="$WORK/delete-indices.txt"
  # Duplicate positions, 1-based, strictly descending, computed
  # from the same dump the dedupe order came from, with the
  # same match rule (default "song", so same-song entries with
  # a different persistent ID are included, not just exact
  # ID repeats): the first occurrence of each song stays,
  # every later occurrence is a position to delete. Descending
  # order is what makes the bridge's deletions safe (a higher
  # deletion never shifts a lower position still to delete).
  # The bridge's own count check (snapshot count minus unique
  # count equals delete count) refuses before deleting if
  # these positions ever disagree with the dedupe order.
  step "compute dedupe delete positions for $target" "$PY" -m seter_shuffle.cli dedupe-positions --library "$DUMP" --match "$DEDUPE_MATCH" --out "$delete_txt" || return 1
  if step "dedupe in place for $target" osascript "$BRIDGE/dedupe-in-place.applescript" "$target" "$ORDER_TXT" "$delete_txt" "$run_backup"; then
    if [ -f "$backup" ]; then
      cp "$backup" "$backup.prev"
      log "previous backup preserved at $backup.prev"
    fi
    cp "$run_backup" "$backup"
    log "GATE: in-place dedupe verified for $target (pre-run snapshot installed as backup at $backup; per-run snapshot kept at $run_backup)"
    ls -t "$STATE"/backup-*.run-*.txt 2>/dev/null | tail -n +11 | while read -r f; do rm -f "$f"; done || true
    notify "SeTeR Shuffle: $target deduped in place"
    return 0
  fi
  log "GATE FAILED: in-place dedupe failed for $target"
  notify "SeTeR Shuffle: in-place dedupe failed for $target"
  # Skip the redundant undo restore (v3.0.7 logic): if the
  # bridge already restored from its snapshot, undo would
  # only rebuild the same snapshot again. Only lines since
  # this dedupe's STEP line count.
  dedupe_step_line="$(grep -n "STEP: dedupe in place for $target" "$LOG" | tail -n 1 | cut -d: -f1)"
  if [ -n "$dedupe_step_line" ] && tail -n +"$dedupe_step_line" "$LOG" | grep -q "restored from backup" && ! tail -n +"$dedupe_step_line" "$LOG" | grep -q "CRITICAL"; then
    log "in-place dedupe already restored the playlist from its per-run snapshot at $run_backup; skipping the redundant undo restore (v3.0.7); main backup at $backup was NOT overwritten by this failed run"
    return 1
  fi
  if [ -f "$run_backup" ]; then
    log "per-run snapshot exists at $run_backup; attempting restore via undo (undo itself tries both mappings, v3.0.5); main backup at $backup was NOT overwritten by this failed run"
    if step "restore $target from per-run snapshot" osascript "$BRIDGE/undo.applescript" "$target" "$run_backup" "forward"; then
      log "restore from per-run snapshot succeeded; playlist is back to its pre-run state"
    else
      restore_step_line="$(grep -n "STEP: restore $target from per-run snapshot" "$LOG" | tail -n 1 | cut -d: -f1)"
      if [ -n "$restore_step_line" ] && tail -n +"$restore_step_line" "$LOG" | grep -q "PLAYLIST_UNTOUCHED"; then
        log "restore from per-run snapshot failed while reading the playlist before any change (PLAYLIST_UNTOUCHED); playlist is untouched, NOT partial; re-run undo with backup $run_backup (main backup at $backup is still the last good state)"
      else
        log "CRITICAL: restore from per-run snapshot also failed; playlist may be partial; re-run undo with backup $run_backup (main backup at $backup is still the last good state)"
        return 2
      fi
    fi
  else
    log "no per-run snapshot was written, so the in-place dedupe failed before any playlist change; playlist untouched and main backup at $backup untouched"
  fi
  return 1
}

case "$CMD" in
  audit)
    log "audit (no Music changes)"
    step "audit" "$PY" -m seter_shuffle.cli audit --library "$DUMP" || exit 1
    log "audit done; nothing was applied"
    ;;
  flowPreview)
    log "flowPreview (no Music changes)"
    step "flowPreview" "$PY" -m seter_shuffle.cli flowPreview --library "$DUMP" --out "$ORDER" --order-txt "$ORDER_TXT" --playlist "$(options_flow_target)" || exit 1
    log "flowPreview done; nothing was applied"
    ;;
  flow)
    TARGET_PLAYLIST="$(options_flow_target)"
    step "compute flow order" "$PY" -m seter_shuffle.cli flow --library "$DUMP" --out "$ORDER" --order-txt "$ORDER_TXT" --playlist "$TARGET_PLAYLIST" || exit 1
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
    # Bash 3.2 (macOS /bin/bash) under set -u treats expanding an
    # empty array as an unbound variable, so the old code died
    # here (2026-10-29, mode 39) on every blank-size shuffle:
    # dump succeeded, then an unbound-variable error before any
    # compute or apply, with no playlist change. There is
    # deliberately no array in this block: each
    # branch spells out its full argument list, so blank/all
    # expands to nothing and a set size passes exactly one
    # --size flag. (A sized in-place shuffle is already refused
    # before the dump, so the size+source branch below is
    # unreachable in practice; it is kept for safety, not use.)
    if [ -n "$SHUFFLE_SIZE" ] && [ "$SHUFFLE_SIZE" != "all" ]; then
      if [ -n "${SOURCE_PLAYLIST:-}" ]; then
        step "compute shuffle order" "$PY" -m seter_shuffle.cli shuffle --library "$DUMP" --out "$ORDER" --order-txt "$ORDER_TXT" --allow-duplicates --size "$SHUFFLE_SIZE" || exit 1
      else
        step "compute shuffle order" "$PY" -m seter_shuffle.cli shuffle --library "$DUMP" --out "$ORDER" --order-txt "$ORDER_TXT" --size "$SHUFFLE_SIZE" || exit 1
      fi
    elif [ -n "${SOURCE_PLAYLIST:-}" ]; then
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
    step "compute dedupe order" "$PY" -m seter_shuffle.cli dedupe --library "$DUMP" --out "$ORDER" --order-txt "$ORDER_TXT" --match "$DEDUPE_MATCH" || exit 1
    # Skip the apply entirely when there is nothing to remove: a
    # rebuild of an already-clean playlist is pure risk for zero
    # gain, and on a sorted playlist it would also re-exercise the
    # delete/re-add loop for nothing. The order count equals the
    # dump count exactly when the playlist holds no duplicates.
    # A clean playlist needs no mapping at all: nothing is built.
    dump_count="$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d["tracks"]))' "$DUMP")"
    order_count="$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["count"])' "$ORDER")"
    if [ "$order_count" = "$dump_count" ]; then
      log "dedupe done: no duplicate entries in \"$TARGET_PLAYLIST\" ($dump_count songs); nothing was applied"
      notify "SeTeR Shuffle: $TARGET_PLAYLIST already clean, nothing applied"
    else
      # In-place dedupe (v3.0.9, superseding presence dedupe
      # v3.0.8 before v3.0.8 was ever published): Spencer's
      # cap is 1-2 rebuilds max, and deleting only the
      # duplicate entries costs 0 rebuilds on success. No
      # mapping is needed, probed, or trialled at all, and no
      # mapping is recorded: the next shuffle or flow
      # self-probes the now-clean playlist for its true
      # mapping. Trial-dedupe (v3.0.4-3.0.7) and presence
      # dedupe (v3.0.8) are retained in the code but no longer
      # called for dedupe.
      log "dedupe: $dump_count entries, $order_count unique songs; in-place delete of $((dump_count - order_count)) duplicate entries (0 rebuilds on success, no mapping recorded)"
      dedupe_in_place "$TARGET_PLAYLIST" || exit 1
      log "dedupe done: playlist holds the $order_count unique songs, deduped in place; no mapping was recorded from this run"
    fi
    ;;
esac
