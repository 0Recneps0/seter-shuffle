#!/bin/bash
# run.sh (SeTeR Shuffle, Python core)
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
#   ./run.sh daily [playlist]       the daily run (what daily.sh calls:
#                                   daily.sh is a shortcut for this):
#                                   auto self-probe each target, dedupe,
#                                   shuffle, flow, rediscover, and a
#                                   once-a-day library manifest; AI
#                                   tagging is always on for the daily
#                                   run; logs to $STATE/daily.log
#   ./run.sh daily-status           read-only daily health report: plist,
#                                   loaded job, last run, AI state,
#                                   newest manifest; changes nothing
#   ./run.sh organize               move loose *.bak-YYYYMMDD-HHMMSS
#                                   files into previous-versions/<stamp>/
#                                   buckets; moves only, never deletes
#   ./run.sh backups [playlist]     read-only list of restore points:
#                                   the playlist's main backup, .prev,
#                                   .pre-undo / .fix-snapshot, and
#                                   per-run snapshots, each with song
#                                   count and time; with no playlist,
#                                   every backup-*.txt in $STATE
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

# Menu colors (v3.0.11 exp 2026-11-20.6): only when stdout is a
# terminal. With piped or redirected stdout every var is empty,
# so subcommand and log output stays byte-identical to before
# (plain text, no escape bytes anywhere). The palette is cyan
# for the banner and choice lines (magenta for the SHUFFLE
# block), with green / yellow / red / dim only as status colors
# (ON, env-wins notes, errors). Menu
# functions use ${C_...:-} expansions, never bare $C_..., so
# they still work when the vars are unset (the test harness
# extracts the functions without these definitions).
if [ -t 1 ]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_ITALIC=$'\033[3m'
  C_ITALIC_OFF=$'\033[23m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
  C_BOLD_CYAN=$'\033[1;36m'
  C_BOLD_MAGENTA=$'\033[1;35m'
  C_BOLD_GREEN=$'\033[1;32m'
  C_BOLD_RED=$'\033[1;31m'
  C_DIM_YELLOW=$'\033[2;33m'
else
  C_RESET=
  C_BOLD=
  C_DIM=
  C_ITALIC=
  C_ITALIC_OFF=
  C_RED=
  C_GREEN=
  C_YELLOW=
  C_CYAN=
  C_BOLD_CYAN=
  C_BOLD_MAGENTA=
  C_BOLD_GREEN=
  C_BOLD_RED=
  C_DIM_YELLOW=
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
BRIDGE="$ROOT/bridge"
# SETER_STATE_DIR is a test hook (and the daily run's state
# override): when set, state, logs, mappings, and the lock all
# live there instead of ~/Library/Logs/seter-shuffle-python.
STATE="${SETER_STATE_DIR:-$HOME/Library/Logs/seter-shuffle-python}"
LOG="$STATE/run.log"
# The daily run logs to daily.log, not run.log (exp-2026-11-26.1,
# when daily.sh became a shortcut for run.sh daily): $1 is known
# this early, and the python check below already logs.
if [ "${1:-}" = "daily" ]; then LOG="$STATE/daily.log"; fi
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

# First line of a settings file, whitespace-trimmed; empty when
# the file is missing or unreadable. Only for one-line
# number/flag files, never for playlist names (their spaces
# matter).
options_read_file() {
  local file="$1" val
  if [ -f "$(options_dir)/$file" ]; then
    val="$(head -n 1 "$(options_dir)/$file" 2>/dev/null | tr -d ' \t\r\n')"
    printf '%s' "$val"
  fi
}

# Atomically write one line to a settings file (mktemp + mv, so
# a crash can never leave a half-written file behind, and no
# stray temp file is left after a successful write).
options_write_file() {
  local file="$1" value="$2" dir tmp
  dir="$(options_dir)"
  mkdir -p "$dir" || return 1
  tmp="$(mktemp "$dir/.$file.XXXXXX")" || return 1
  printf '%s\n' "$value" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$dir/$file" || { rm -f "$tmp"; return 1; }
  return 0
}

# Read a one-number settings file, clamped to [lo, hi]; a
# missing, empty, or non-numeric file reads as the default (the
# same rule as options_probe_max_age, which keeps its own
# implementation below). Leading zeros are stripped first, and
# a value with more than four digits is above every range here
# (largest hi is 1000), so it clamps without ever reaching an
# arithmetic comparison that could overflow.
options_read_int_file() {
  local file="$1" default="$2" lo="$3" hi="$4" val
  val="$(options_read_file "$file")"
  case "$val" in
    ''|*[!0-9]*) printf '%s' "$default"; return 0 ;;
  esac
  while [ "${#val}" -gt 1 ] && [ "${val#0}" != "$val" ]; do
    val="${val#0}"
  done
  case "$val" in
    ?????*) printf '%s' "$hi"; return 0 ;;
  esac
  if [ "$val" -gt "$hi" ]; then
    printf '%s' "$hi"
  elif [ "$val" -lt "$lo" ]; then
    printf '%s' "$lo"
  else
    printf '%s' "$val"
  fi
}

# Effective AI blend (0.0-1.0, default 0.6): the ai-blend file,
# garbage reads as the default, out of range clamps into range.
options_ai_blend() {
  local val int frac
  val="$(options_read_file ai-blend)"
  case "$val" in
    ''|*[!0-9.]*) printf '0.6'; return 0 ;;
    *.*.*) printf '0.6'; return 0 ;;
    *.) printf '0.6'; return 0 ;;
  esac
  int="${val%%.*}"
  case "$val" in
    *.*) frac="${val#*.}" ;;
    *) frac="" ;;
  esac
  case "$int" in
    ''|*[!0-9]*) printf '0.6'; return 0 ;;
  esac
  while [ "${#int}" -gt 1 ] && [ "${int#0}" != "$int" ]; do
    int="${int#0}"
  done
  if [ "$int" -gt 1 ]; then printf '1'; return 0; fi
  if [ "$int" -eq 1 ]; then printf '1'; return 0; fi
  printf '%s' "$val"
}

# Effective AI mood cost (0-10, default 4; 0 = moods don't steer
# the Flow walk).
options_ai_mood_cost() {
  options_read_int_file ai-mood-cost 4 0 10
}

# Effective Flow size in songs (10-200, default 50). This is
# Settings.flow_size, the Flow order length — not the CLI
# --size output cap.
options_flow_size() {
  options_read_int_file flow-size 50 10 200
}

# Effective Flow pool cap (0-1000, default 400; 0 = no cap).
options_flow_pool_max() {
  options_read_int_file flow-pool-max 400 0 1000
}

# Effective artist spacing (1-5, default 2; 1 = just not
# back-to-back).
options_artist_spacing() {
  options_read_int_file artist-spacing 2 1 5
}

# Effective Rediscover size in songs (5-500, default 30). Maps
# to Settings.rediscover_min: for his ~950-song library the min
# is the effective target.
options_rediscover_size() {
  options_read_int_file rediscover-size 30 5 500
}

# Effective Rediscover max per artist (0-10, default 3;
# 0 = no limit).
options_rediscover_max_per_artist() {
  options_read_int_file rediscover-max-per-artist 3 0 10
}

# Effective Rediscover cooldown in days (0-90, default 14;
# 0 = off).
options_rediscover_cooldown_days() {
  options_read_int_file rediscover-cooldown-days 14 0 90
}

# Effective Rediscover stale-after in days (7-365, default 60):
# how long unplayed before a song counts as forgotten.
options_rediscover_stale_days() {
  options_read_int_file rediscover-stale-days 60 7 365
}

# Effective "feat." rule: an env var set before this process
# started (OPTIONS_FEATURING_ENV_SET, recorded by
# load_persisted_options) decides; otherwise the
# featuring-same-artist file, which holds "1" or "0"; absent
# file (or anything unreadable) = 1, on. The loader exports
# the file's value into the env, so a menu child inherits it,
# and the setter below keeps the env in step with the file.
options_featuring_on() {
  local val
  if [ -n "${OPTIONS_FEATURING_ENV_SET:-}" ]; then
    case "$(printf '%s' "${SETER_FEATURING_SAME_ARTIST:-}" | tr '[:upper:]' '[:lower:]')" in
      1|true|yes|on) return 0 ;;
      *) return 1 ;;
    esac
  fi
  if [ -f "$(options_dir)/featuring-same-artist" ]; then
    val="$(options_read_file featuring-same-artist | tr '[:upper:]' '[:lower:]')"
    case "$val" in
      0|false|no|off) return 1 ;;
    esac
  fi
  return 0
}

options_set_featuring() {
  if options_write_file featuring-same-artist "$1"; then
    export SETER_FEATURING_SAME_ARTIST="$1"
    return 0
  fi
  return 1
}

# Effective dedupe match (song or id): SETER_DEDUPE_MATCH wins
# when set (run.sh validates it at startup); otherwise the
# dedupe-match file, which holds "song" or "id"; absent file
# (or anything unreadable) = song. Song = same artist + title
# counts as a duplicate; id = same track ID only.
options_dedupe_match() {
  local val
  if [ -n "${SETER_DEDUPE_MATCH:-}" ]; then
    printf '%s' "$SETER_DEDUPE_MATCH"
    return 0
  fi
  if [ -f "$(options_dir)/dedupe-match" ]; then
    val="$(options_read_file dedupe-match | tr '[:upper:]' '[:lower:]')"
    case "$val" in
      id|song) printf '%s' "$val"; return 0 ;;
    esac
  fi
  printf 'song'
}

# Write the dedupe-match file and keep the in-process
# DEDUPE_MATCH in step with it (same stale-env rule as the
# other setters; menu children are fresh processes that run
# the loader and read the file).
options_set_dedupe_match() {
  if options_write_file dedupe-match "$1"; then
    DEDUPE_MATCH="$1"
    return 0
  fi
  return 1
}

# Write a numeric settings file and keep the in-process env in
# step with it (same stale-env rule as split collabs / flow
# source): without the export, a menu process that exported the
# old value at startup would hand its children the old value
# after the user changed it.
options_set_ai_blend() {
  if options_write_file ai-blend "$1"; then export SETER_AI_BLEND="$1"; return 0; fi
  return 1
}

options_set_ai_mood_cost() {
  if options_write_file ai-mood-cost "$1"; then export SETER_AI_MOOD_COST="$1"; return 0; fi
  return 1
}

options_set_flow_size() {
  if options_write_file flow-size "$1"; then export SETER_FLOW_SIZE="$1"; return 0; fi
  return 1
}

options_set_flow_pool_max() {
  if options_write_file flow-pool-max "$1"; then export SETER_FLOW_POOL_MAX="$1"; return 0; fi
  return 1
}

options_set_artist_spacing() {
  if options_write_file artist-spacing "$1"; then export SETER_ARTIST_SPACING="$1"; return 0; fi
  return 1
}

options_set_rediscover_size() {
  if options_write_file rediscover-size "$1"; then export SETER_REDISCOVER_SIZE="$1"; return 0; fi
  return 1
}

options_set_rediscover_max_per_artist() {
  if options_write_file rediscover-max-per-artist "$1"; then export SETER_REDISCOVER_MAX_PER_ARTIST="$1"; return 0; fi
  return 1
}

options_set_rediscover_cooldown_days() {
  if options_write_file rediscover-cooldown-days "$1"; then export SETER_REDISCOVER_COOLDOWN_DAYS="$1"; return 0; fi
  return 1
}

options_set_rediscover_stale_days() {
  if options_write_file rediscover-stale-days "$1"; then export SETER_REDISCOVER_STALE_DAYS="$1"; return 0; fi
  return 1
}

# Validate typed input for a numeric menu choice. $1 = input,
# $2 = low, $3 = high. On success prints the cleaned number;
# on failure prints nothing and returns 1 (out of range) or 2
# (not a number), so the caller can print the matching plain
# message and stay in the submenu with the old value kept.
options_validate_number() {
  local val="$1" lo="$2" hi="$3"
  case "$val" in
    ''|*[!0-9]*) return 2 ;;
  esac
  while [ "${#val}" -gt 1 ] && [ "${val#0}" != "$val" ]; do
    val="${val#0}"
  done
  case "$val" in
    ?????*) return 1 ;;
  esac
  if [ "$val" -lt "$lo" ] || [ "$val" -gt "$hi" ]; then
    return 1
  fi
  printf '%s' "$val"
  return 0
}

# Validate typed input for the AI blend (0, 0.x, 1, 1.0). Same
# contract as options_validate_number: prints the cleaned
# number on success (normalized, so "1.00" comes back "1"),
# returns 1 for a number out of range, 2 for not a number.
options_validate_blend() {
  local val="$1" int frac
  case "$val" in
    ''|*[!0-9.]*) return 2 ;;
    *.*.*) return 2 ;;
    *.) return 2 ;;
  esac
  int="${val%%.*}"
  case "$val" in
    *.*) frac="${val#*.}" ;;
    *) frac="" ;;
  esac
  case "$int" in
    ''|*[!0-9]*) return 2 ;;
  esac
  if [ -n "$frac" ]; then
    case "$frac" in
      *[!0-9]*) return 2 ;;
    esac
  fi
  while [ "${#int}" -gt 1 ] && [ "${int#0}" != "$int" ]; do
    int="${int#0}"
  done
  if [ "$int" -gt 1 ]; then return 1; fi
  if [ "$int" -eq 1 ]; then
    if [ -n "$frac" ]; then
      case "$frac" in
        *[!0]*) return 1 ;;
      esac
    fi
    printf '1'
    return 0
  fi
  if [ -n "$frac" ]; then
    printf '0.%s' "$frac"
  else
    printf '0'
  fi
  return 0
}

# Dim-yellow "(env SETER_X=Y wins)" suffix for a setting whose
# env var was set before this process started (marker recorded
# by load_persisted_options); empty otherwise. Uses indirect
# expansion, so the caller passes the env var name and its
# marker name, not the values.
options_env_note() {
  local env_name="$1" marker="$2"
  if [ -n "${!marker:-}" ]; then
    printf '%s(env %s=%s wins)%s' "${C_DIM_YELLOW:-}" "$env_name" "${!env_name:-}" "${C_RESET:-}"
  fi
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
# The rest of the Options page (v3.0.11 exp 2026-11-20.6)
# follows the same rule again: each numeric / toggle setting's
# file becomes its env var unless the env was already set, and
# an OPTIONS_*_ENV_SET marker records which case applied, so
# the menu can say the env wins instead of pretending a change
# took effect. The CLI reads all of these env vars itself
# (cli.py _settings_from), so the loader is the only place that
# has to know the file names.
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
  if [ -n "${SETER_AI_BLEND:-}" ]; then
    OPTIONS_AI_BLEND_ENV_SET=1
  else
    export SETER_AI_BLEND="$(options_ai_blend)"
  fi
  if [ -n "${SETER_AI_MOOD_COST:-}" ]; then
    OPTIONS_AI_MOOD_COST_ENV_SET=1
  else
    export SETER_AI_MOOD_COST="$(options_ai_mood_cost)"
  fi
  if [ -n "${SETER_FLOW_SIZE:-}" ]; then
    OPTIONS_FLOW_SIZE_ENV_SET=1
  else
    export SETER_FLOW_SIZE="$(options_flow_size)"
  fi
  if [ -n "${SETER_FLOW_POOL_MAX:-}" ]; then
    OPTIONS_FLOW_POOL_MAX_ENV_SET=1
  else
    export SETER_FLOW_POOL_MAX="$(options_flow_pool_max)"
  fi
  if [ -n "${SETER_ARTIST_SPACING:-}" ]; then
    OPTIONS_ARTIST_SPACING_ENV_SET=1
  else
    export SETER_ARTIST_SPACING="$(options_artist_spacing)"
  fi
  if [ -n "${SETER_REDISCOVER_SIZE:-}" ]; then
    OPTIONS_REDISCOVER_SIZE_ENV_SET=1
  else
    export SETER_REDISCOVER_SIZE="$(options_rediscover_size)"
  fi
  if [ -n "${SETER_REDISCOVER_MAX_PER_ARTIST:-}" ]; then
    OPTIONS_REDISCOVER_MAX_PER_ARTIST_ENV_SET=1
  else
    export SETER_REDISCOVER_MAX_PER_ARTIST="$(options_rediscover_max_per_artist)"
  fi
  if [ -n "${SETER_REDISCOVER_COOLDOWN_DAYS:-}" ]; then
    OPTIONS_REDISCOVER_COOLDOWN_DAYS_ENV_SET=1
  else
    export SETER_REDISCOVER_COOLDOWN_DAYS="$(options_rediscover_cooldown_days)"
  fi
  if [ -n "${SETER_REDISCOVER_STALE_DAYS:-}" ]; then
    OPTIONS_REDISCOVER_STALE_DAYS_ENV_SET=1
  else
    export SETER_REDISCOVER_STALE_DAYS="$(options_rediscover_stale_days)"
  fi
  if [ -n "${SETER_FEATURING_SAME_ARTIST:-}" ]; then
    OPTIONS_FEATURING_ENV_SET=1
  elif [ -f "$(options_dir)/featuring-same-artist" ]; then
    if options_featuring_on; then
      export SETER_FEATURING_SAME_ARTIST=1
    else
      export SETER_FEATURING_SAME_ARTIST=0
    fi
  fi
  if [ -n "${SETER_DEDUPE_MATCH:-}" ]; then
    OPTIONS_DEDUPE_ENV_SET=1
  elif [ -f "$(options_dir)/dedupe-match" ]; then
    DEDUPE_MATCH="$(options_dedupe_match)"
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
  audit|flowPreview|flow|shuffle|rediscover-preview|rediscover|undo|dedupe|restore|probe|probe-keep|sortprobe|selfprobe|menu|daily|daily-status|organize|backups) ;;
  *)
    echo "usage: $0 {audit|flowPreview|flow|shuffle [playlist] [size]|rediscover-preview|rediscover|undo <playlist>|dedupe <playlist>|restore <playlist> <backup-txt>|probe|probe-keep|sortprobe <throwaway> <target> <sort-label>|selfprobe <playlist>|menu|daily [playlist]|daily-status|organize|backups [playlist]} (run with no arguments in a terminal to open the menu)" >&2
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
# daily is listed here too, but only because it takes the lock
# itself below: a dry run must skip the lock, and a refusal must
# say DAILY SKIPPED, which the generic refusal cannot.
case "$CMD" in
  audit|flowPreview|rediscover-preview|menu|daily-status|organize|backups|daily) ;;
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

# ---- daily mode (exp-2026-11-26.1) ------------------------------------
# The daily run, matching stable v2.6's daily behavior as closely as
# the Python build allows. This used to be daily.sh; since
# exp-2026-11-26.1 it lives here as `run.sh daily`, and daily.sh
# is only a shortcut that execs it. The plist still calls
# daily.sh with the playlist arg, so the interface is unchanged:
#   ./run.sh daily "My New Sandwich Recipe"
#   ./run.sh daily                      # default playlist, same name
#   1. Save a once-a-day library manifest (ID, artist, album, title),
#      kept 14 days, under the install directory's backups/.
#   2. Dedupe the daily playlist (no-op when it is already clean),
#      then shuffle it in place (v2.6 dailyRemoveDuplicates = true).
#   3. Refresh the Flow target playlist (the target and the
#      source pool are configurable, default "SeTeR Flow" from
#      the whole library).
#   4. Refresh "SeTeR Rediscover" and record history only after a
#      successful apply (run.sh does that part).
#   Shuffle, Flow, and Rediscover each stamp their playlist
#   description "Last reshuffled: <Mac local date/time at the
#   verified apply>", so every daily-refreshed playlist shows that
#   morning's time, not a stale manual-run time. Dedupe does not stamp.
#
# HARD RULES (do not weaken these for convenience):
# - This run AUTO SELF-PROBES (v3.0.2). Before the mapping
#   check, it runs ./run.sh selfprobe on EACH target it touches
#   (the daily playlist, the Flow target, AND "SeTeR Rediscover"), refreshing that
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
# - IN-PLACE DEDUPE BREAKS THE OLD DEADLOCK (v3.0.9,
#   superseding presence dedupe v3.0.8 and trial-dedupe
#   v3.0.4): the duplicate-entry refusal is unchanged, so a
#   self-probe on a playlist with duplicate entries still
#   refuses and changes nothing. But the daily run no longer
#   stops there: when ANY target's probe refuses ONLY
#   on duplicate entries (the probe output says so), the
#   daily run attempts ./run.sh dedupe on that target,
#   which deletes only the duplicate entries in place and
#   records no mapping, then re-probes the clean target
#   once for a fresh mapping. A probe failure for any other
#   reason still stops the run immediately, a failed
#   in-place dedupe stops it before shuffle, flow, and
#   rediscover, and a re-probe that still refuses (or
#   fails any other way) stops it with no second dedupe
#   attempt. EXPERIMENTAL 2026-10-31: this fallback used
#   to cover only the daily playlist, so on 2026-10-31 the
#   daily run cleaned the main playlist, then exited at
#   the Rediscover probe's duplicate refusal before
#   shuffle, flow, or rediscover ever ran. Rediscover and
#   Flow are generated playlists, but a doubled generated
#   playlist stalls the whole daily run the same way a
#   doubled main playlist does, and in-place dedupe is
#   the same safe repair for them (snapshot before,
#   verified after, 0 rebuilds, no mapping recorded).
#   The re-probe after a fallback dedupe is safe against
#   the shared-snapshot rule below: the refused probe
#   changed nothing and wrote no snapshot, so there is no
#   pending restore for the re-probe to overwrite, and
#   the re-probe is on the SAME target, never a different
#   target while a restore is pending.
# - Dry runs (SETER_DAILY_DRY_RUN=1, a test hook never used by
#   launchd) do NOT run the self-probes, because a dry run
#   changes nothing; they log the planned probes instead and
#   then run the mapping check on the recorded mappings.
# - This run NEVER touches the v2.6 install
#   (~/Documents/SeTeRShuffle) or its launchd job (com.seter.daily).
#   Migration disables that job only when migrate-to-python.sh is
#   run explicitly with --confirm; this script does not do it.
# - State, logs, and Rediscover history paths are the same ones
#   run.sh uses, so the daily run and manual runs share backups
#   and history instead of forking them.
# - AI tagging is ALWAYS ON for the daily run (exp-2026-11-26.1):
#   the daily path exports SETER_AI=1 before the flow step, so
#   Flow tags with AI even if the ai-enabled marker file is
#   gone. Manual runs are unchanged: they still follow the
#   marker and SETER_AI.
#
# Test hooks (used by the unit tests only, never by launchd):
#   SETER_STATE_DIR       override the state directory
#   SETER_DAILY_DRY_RUN=1 pass the mapping pre-check, print the
#                         planned steps, and exit 0 without
#                         calling run.sh or Music at all (the auto
#                         self-probes are logged as planned, not run).
if [ "$CMD" = "daily" ]; then
  DAILY_PLAYLIST="${2:-My New Sandwich Recipe}"
  PLAYLIST="$DAILY_PLAYLIST"
  BACKUP_DIR="${SETER_BACKUP_DIR:-$ROOT/backups}"
  REDISCOVER_PLAYLIST="SeTeR Rediscover"
  # FLOW_PLAYLIST and FLOW_SOURCE are set by load_flow_settings below
  # (env wins, else the flow-target-playlist / flow-source-playlist
  # files under the SeTeRShuffle settings dir, else "SeTeR Flow" /
  # the whole library), so the daily run and the menu read the same
  # settings and agree.

  mkdir -p "$BACKUP_DIR" 2>/dev/null || true

  daily_die() { log "DAILY FAILED: $*"; notify "SeTeR Shuffle daily run failed: $*"; exit 1; }

  # Probe cadence (v3.0.11). Default 0 = self-probe every target every
  # day, exactly as before. SETER_PROBE_MAX_AGE_HOURS=N (1..40) skips a
  # target's self-probe while its recorded mapping is younger than N
  # hours: each probe rebuilds the playlist twice (rotate + restore),
  # which is a lot of add/remove churn to sync every day. The mapping
  # check below still refuses anything older than 48 hours, and the
  # real build still verifies after writing and restores on failure.
  # Persisted probe cadence (menu Options submenu, v3.0.11 exp
  # 2026-11-20.3): the probe-max-age-hours file under the
  # SeTeRShuffle settings dir (same dir the AI marker already
  # uses; SETER_AI_DIR is a test hook, never set by a real run).
  # An env var already set wins over the file, so a one-off
  # override still works. The file holds one number; the
  # validation below (non-numeric reads as 0, over 40 clamps to
  # 40) covers a hand-edited file.
  load_probe_max_age() {
    local dir val
    if [ -n "${SETER_PROBE_MAX_AGE_HOURS:-}" ]; then
      return 0
    fi
    dir="${SETER_AI_DIR:-$HOME/Documents/SeTeRShuffle}"
    if [ -f "$dir/probe-max-age-hours" ]; then
      val="$(head -n 1 "$dir/probe-max-age-hours" 2>/dev/null | tr -d ' \t\r\n')"
      case "$val" in
        ''|*[!0-9]*) return 0 ;;
      esac
      export SETER_PROBE_MAX_AGE_HOURS="$val"
    fi
    return 0
  }
  load_probe_max_age
  PROBE_MAX_AGE_HOURS="${SETER_PROBE_MAX_AGE_HOURS:-0}"
  case "$PROBE_MAX_AGE_HOURS" in ''|*[!0-9]*) PROBE_MAX_AGE_HOURS=0 ;; esac
  [ "$PROBE_MAX_AGE_HOURS" -gt 40 ] && PROBE_MAX_AGE_HOURS=40

  # Flow playlists (v3.0.11 exp 2026-11-20.5): the Flow source pool
  # and target playlist, mirroring run.sh's options_flow_source /
  # options_flow_target. An env var already set wins over the file,
  # so a one-off override still works; otherwise the
  # flow-source-playlist / flow-target-playlist files under the
  # SeTeRShuffle settings dir (same dir the probe-age file uses);
  # absent files mean the whole library and "SeTeR Flow". A bad
  # file (empty, or only whitespace) reads as the default, exactly
  # as run.sh reads it, and "library" (any case) as the source
  # means the whole library. The resolved values are exported so
  # the run.sh flow step below (a child process) resolves the same
  # settings: daily and menu can never disagree about which
  # playlist Flow reads from or writes to.
  load_flow_settings() {
    local dir val lower trimmed
    dir="${SETER_AI_DIR:-$HOME/Documents/SeTeRShuffle}"
    if [ -n "${SETER_FLOW_SOURCE:-}" ]; then
      val="$SETER_FLOW_SOURCE"
    elif [ -f "$dir/flow-source-playlist" ]; then
      val="$(head -n 1 "$dir/flow-source-playlist" 2>/dev/null)"
      val="${val%$'\r'}"
      val="$(printf '%s' "$val" | sed 's/[[:space:]]*$//')"
    else
      val="library"
    fi
    lower="$(printf '%s' "$val" | tr '[:upper:]' '[:lower:]' | tr -d ' \t\r')"
    if [ -z "$lower" ] || [ "$lower" = "library" ]; then
      export SETER_FLOW_SOURCE="library"
    else
      export SETER_FLOW_SOURCE="$val"
    fi
    if [ -n "${SETER_FLOW_TARGET:-}" ]; then
      val="$SETER_FLOW_TARGET"
    elif [ -f "$dir/flow-target-playlist" ]; then
      val="$(head -n 1 "$dir/flow-target-playlist" 2>/dev/null)"
      val="${val%$'\r'}"
      val="$(printf '%s' "$val" | sed 's/[[:space:]]*$//')"
    else
      val="SeTeR Flow"
    fi
    trimmed="$(printf '%s' "$val" | tr -d ' \t\r')"
    if [ -n "$trimmed" ]; then
      export SETER_FLOW_TARGET="$val"
    else
      export SETER_FLOW_TARGET="SeTeR Flow"
    fi
    return 0
  }
  load_flow_settings
  FLOW_SOURCE="$SETER_FLOW_SOURCE"
  FLOW_PLAYLIST="$SETER_FLOW_TARGET"
  if [ "$FLOW_SOURCE" = "library" ]; then
    FLOW_SOURCE_LABEL="whole library"
  else
    FLOW_SOURCE_LABEL="'$FLOW_SOURCE'"
  fi

  # Auto self-probe one target before the mapping check. Return
  # codes: 0 on success; 2 when the probe refused ONLY on
  # duplicate entries (the caller may then try in-place
  # dedupe, which is the one repair that does not need a probe); 1 on any other
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
      log "daily auto self-probe for '$target' refused on duplicate entries only; in-place dedupe will be attempted (it deletes only the duplicate entries, 0 rebuilds on success, and records no mapping)"
      return 2
    fi
    log "DAILY FAILED: auto self-probe failed for '$target'; daily stopped before any build, dedupe, or rediscover, and before probing the other target."
    log "DAILY FAILED: if the probe could not restore '$target', it may hold the rotation order; its snapshot is at $snapshot; restore it with ./run.sh restore '$target' '$snapshot', then re-run the daily run (it will self-probe again)."
    return 1
  }

  # Probe one target, with the duplicate-only in-place dedupe
  # fallback shared by all three daily targets (EXPERIMENTAL
  # 2026-10-31; before this, only the daily playlist had it).
  # Return codes: 0 when the target ends with a fresh mapping
  # (probe OK, or dedupe succeeded and the re-probe passed);
  # 1 on any failure, in which case the caller stops the whole
  # daily run before probing another target or building
  # anything. Exactly one dedupe attempt per target, ever: a
  # re-probe that still refuses on duplicates means the dedupe
  # did not clean the list, and trying dedupe again on top of
  # that state would be guessing, so the run stops instead.
  mapping_is_younger_than_cap() {
    local target="$1" map_file ts
    [ "$PROBE_MAX_AGE_HOURS" -gt 0 ] || return 1
    map_file="$(mapping_file_for "$target")"
    [ -f "$map_file" ] || return 1
    ts="$(grep '^TIMESTAMP: ' "$map_file" | head -n 1 | sed 's/^TIMESTAMP: //')"
    case "$ts" in ''|*[!0-9]*) return 1 ;; esac
    [ $(( $(date +%s) - ts )) -lt $((PROBE_MAX_AGE_HOURS * 3600)) ]
  }
  probe_target() {
    local target="$1" status=0
    if mapping_is_younger_than_cap "$target"; then
      log "daily self-probe skipped for '$target': mapping is under $PROBE_MAX_AGE_HOURS hours old (SETER_PROBE_MAX_AGE_HOURS)"
      return 0
    fi
    auto_self_probe "$target" || status=$?
    if [ "$status" = "0" ]; then
      return 0
    fi
    if [ "$status" != "2" ]; then
      return 1
    fi
    log "daily in-place dedupe attempt for '$target' (probe refused on duplicates)"
    if ! "$ROOT/run.sh" dedupe "$target" >> "$LOG" 2>&1; then
      log "DAILY FAILED: in-place dedupe failed for '$target'; daily stopped before shuffle, flow, and rediscover"
      return 1
    fi
    log "daily in-place dedupe cleaned '$target'; re-probing the clean playlist for a fresh mapping"
    status=0
    auto_self_probe "$target" || status=$?
    if [ "$status" = "0" ]; then
      return 0
    fi
    if [ "$status" = "2" ]; then
      log "DAILY FAILED: re-probe for '$target' still refused on duplicate entries after the fallback dedupe; daily stopped with no second dedupe attempt"
    fi
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

  # One run at a time. A dry run changes nothing, so it never locks.
  # The lock itself is taken here, not by the generic lock above:
  # a dry run must skip it, and a refusal must say DAILY SKIPPED.
  # The top-level EXIT trap releases it; no second trap is set
  # here, so the WORK cleanup in that trap is never dropped.
  if [ -z "${SETER_DAILY_DRY_RUN:-}" ]; then
    if ! acquire_lock "run.sh daily"; then
      log "DAILY SKIPPED: another SeTeR run is in progress: $LOCK_HOLDER"
      notify "SeTeR Shuffle daily run skipped: another run is in progress"
      exit 3
    fi
  fi

  log "daily run starting for playlist '$PLAYLIST'"

  # Auto self-probe each target, in order, BEFORE the mapping
  # check and before any build. A failure in any probe stops
  # the run before the next probe (shared snapshot file) and
  # before anything else is touched. A duplicate-only failure
  # for any target triggers probe_target's in-place dedupe
  # plus one re-probe (v3.0.9 for the daily playlist,
  # EXPERIMENTAL 2026-10-31 for Rediscover and Flow): if the
  # dedupe cleans the target and the re-probe passes, the run
  # continues to the mapping check and the normal steps (the
  # later dedupe step then no-ops); if the dedupe or the
  # re-probe fails, the run stops before shuffle, flow, and
  # rediscover. In-place dedupe itself records no mapping;
  # the re-probe is what records the fresh mapping for the
  # clean list, so the mapping check after it is not relying
  # on a mapping that survived the refused probe.
  if [ -n "${SETER_DAILY_DRY_RUN:-}" ]; then
    log "dry run: auto self-probes skipped (dry runs change nothing); planned probes: '$PLAYLIST', '$REDISCOVER_PLAYLIST', '$FLOW_PLAYLIST'"
  else
    probe_target "$PLAYLIST" || exit 1
    probe_target "$REDISCOVER_PLAYLIST" || exit 1
    probe_target "$FLOW_PLAYLIST" || exit 1
  fi

  check_mapping "$PLAYLIST" || exit 1
  check_mapping "$REDISCOVER_PLAYLIST" || exit 1
  check_mapping "$FLOW_PLAYLIST" || exit 1

  if [ -n "${SETER_DAILY_DRY_RUN:-}" ]; then
    log "dry run: mappings OK; planned steps: library manifest, dedupe '$PLAYLIST', shuffle '$PLAYLIST', flow (source $FLOW_SOURCE_LABEL, target '$FLOW_PLAYLIST'), rediscover"
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
    if ! osascript "$BRIDGE/dump-library.applescript" "$DUMP" 2>&1 | tee -a "$LOG"; then
      daily_die "library dump for the daily manifest failed"
    fi
    PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}" "$PY" -m seter_shuffle.cli library-manifest --library "$DUMP" --out "$MANIFEST" >> "$LOG" 2>&1 \
      || daily_die "library manifest write failed"
    log "daily manifest written: $MANIFEST"
    find "$BACKUP_DIR" -name 'library-manifest-*.tsv' -mtime +14 -delete 2>/dev/null || true
  else
    log "daily manifest already exists for today: $MANIFEST"
  fi

  # 2-4. Dedupe, then shuffle, then Flow, then Rediscover. Each
  # step goes through run.sh's own gates (fresh mapping,
  # validate, snapshot, verify, restore on failure). Any failure
  # stops the run here: a failed shuffle must not be followed by
  # a Flow or Rediscover refresh that would burn cooldown on a
  # half-done day. Shuffle, Flow, and Rediscover each stamp their
  # playlist description with the verified apply's local time.
  "$ROOT/run.sh" dedupe "$PLAYLIST" >> "$LOG" 2>&1 || daily_die "dedupe '$PLAYLIST' failed (see $LOG)"
  log "daily dedupe done for '$PLAYLIST'"
  "$ROOT/run.sh" shuffle "$PLAYLIST" >> "$LOG" 2>&1 || daily_die "shuffle '$PLAYLIST' failed (see $LOG)"
  log "daily shuffle done for '$PLAYLIST'"
  # AI is guaranteed on for the daily run: the marker file can be
  # deleted, but the daily Flow still tags with AI. This export is
  # daily-only; manual runs still follow the marker and SETER_AI.
  export SETER_AI=1
  log "daily run: AI tagging is on for this run (SETER_AI=1, even if the ai-enabled marker is gone)"
  "$ROOT/run.sh" flow >> "$LOG" 2>&1 || daily_die "flow failed (see $LOG)"
  log "daily flow done"
  "$ROOT/run.sh" rediscover >> "$LOG" 2>&1 || daily_die "rediscover failed (see $LOG)"
  log "daily rediscover done"

  log "daily run done for '$PLAYLIST'"
  notify "SeTeR Shuffle daily run done for $PLAYLIST"
  exit 0
fi
# ---- end daily mode ----------------------------------------------------

# ---- daily-status (exp-2026-11-26.1) -----------------------------------
# Read-only daily health report: whether the daily launchd job is
# installed and loaded, when it last ran and how it ended, whether
# AI tagging is on, and how fresh the library manifest is. Prints
# plain lines to stdout and exits 0; it takes no lock, dumps
# nothing, and never touches a playlist or a setting file. The
# launchctl check is Mac-only: where launchctl is missing or
# `launchctl list` fails, it says so instead of failing.
if [ "$CMD" = "daily-status" ]; then
  DAILY_PLIST_DIR="${SETER_LAUNCHAGENTS_DIR:-$HOME/Library/LaunchAgents}"
  DAILY_PLIST_PATH="$DAILY_PLIST_DIR/com.seter.python.daily.plist"
  echo "install dir: $ROOT"
  echo "daily plist: $DAILY_PLIST_PATH"
  if [ -f "$DAILY_PLIST_PATH" ]; then
    echo "daily plist: present"
    plist_hour="$(grep -A1 '<key>Hour</key>' "$DAILY_PLIST_PATH" | grep '<integer>' | sed 's/[^0-9]//g' | head -n 1)"
    plist_minute="$(grep -A1 '<key>Minute</key>' "$DAILY_PLIST_PATH" | grep '<integer>' | sed 's/[^0-9]//g' | head -n 1)"
    case "$plist_hour" in ''|*[!0-9]*) plist_hour="?" ;; esac
    case "$plist_minute" in ''|*[!0-9]*) plist_minute="?" ;; esac
    if [ "$plist_minute" != "?" ]; then plist_minute="$(printf '%02d' "$plist_minute")"; fi
    plist_args="$(sed -n '/<key>ProgramArguments<\/key>/,/<\/array>/p' "$DAILY_PLIST_PATH" | sed -n 's/^[[:space:]]*<string>\(.*\)<\/string>[[:space:]]*$/\1/p')"
    plist_script="$(printf '%s\n' "$plist_args" | grep 'daily\.sh$' | head -n 1)"
    plist_playlist="$(printf '%s\n' "$plist_args" | tail -n 1)"
    echo "daily schedule: $plist_hour:$plist_minute"
    echo "daily script: ${plist_script:-unknown}"
    echo "daily playlist: ${plist_playlist:-unknown}"
  else
    echo "daily plist: missing (no daily job installed)"
    echo "daily schedule: unknown"
    echo "daily script: unknown"
    echo "daily playlist: unknown"
  fi
  if ! command -v launchctl >/dev/null 2>&1; then
    echo "daily job loaded: cannot check on this system (no launchctl)"
  elif launchctl_out="$(launchctl list 2>/dev/null)"; then
    if printf '%s\n' "$launchctl_out" | grep -q 'com\.seter\.python\.daily'; then
      echo "daily job loaded: yes"
    else
      echo "daily job loaded: no"
    fi
  else
    echo "daily job loaded: cannot check on this system (launchctl list failed)"
  fi
  DAILY_LOG="$STATE/daily.log"
  if [ ! -f "$DAILY_LOG" ]; then
    echo "last daily run: no daily log yet"
    echo "last daily outcome: unknown"
  else
    last_start="$(grep 'daily run starting' "$DAILY_LOG" | tail -n 1)"
    if [ -z "$last_start" ]; then
      echo "last daily run: no daily run recorded in $DAILY_LOG"
      echo "last daily outcome: unknown"
    else
      echo "last daily run: $last_start"
      start_line="$(grep -n 'daily run starting' "$DAILY_LOG" | tail -n 1 | cut -d: -f1)"
      outcome_line="$(tail -n +"$start_line" "$DAILY_LOG" | grep -m1 -E 'daily run done|DAILY FAILED' || true)"
      if [ -z "$outcome_line" ]; then
        echo "last daily outcome: unknown (no outcome recorded after the last start; the run may still be in progress)"
      elif printf '%s' "$outcome_line" | grep -q 'DAILY FAILED'; then
        echo "last daily outcome: $outcome_line"
      else
        echo "last daily outcome: done"
      fi
    fi
  fi
  if [ -f "$(options_dir)/ai-enabled" ]; then
    echo "AI marker: present ($(options_dir)/ai-enabled)"
  else
    echo "AI marker: absent"
  fi
  if [ -n "${SETER_AI:-}" ]; then
    echo "SETER_AI: $SETER_AI"
  else
    echo "SETER_AI: unset"
  fi
  if options_ai_on; then
    echo "AI tagging for Flow: on"
  else
    echo "AI tagging for Flow: off"
  fi
  # Newest manifest by filename date (the names sort
  # chronologically). A plain glob loop, not ls: with pipefail a
  # failing ls would end the report early under set -e.
  newest_manifest=""
  for manifest_file in "$ROOT/backups"/library-manifest-*.tsv; do
    [ -f "$manifest_file" ] || continue
    newest_manifest="$manifest_file"
  done
  if [ -n "$newest_manifest" ]; then
    echo "newest library manifest: $(basename "$newest_manifest" .tsv | sed 's/^library-manifest-//')"
  else
    echo "newest library manifest: none"
  fi
  exit 0
fi
# ---- end daily-status --------------------------------------------------

# ---- organize (exp-2026-11-26.1) ---------------------------------------
# Move loose *.bak-YYYYMMDD-HHMMSS files left by older installs into
# previous-versions/<stamp>/ buckets, preserving each file's path
# relative to the install dir (e.g. seter_shuffle/cli.py.bak-... ->
# previous-versions/<stamp>/seter_shuffle/cli.py). Moves only:
# nothing is deleted, no live file is touched, and the sweep stays
# inside the install tree (top level, bridge/, seter_shuffle/), so
# $STATE and the v2.6 install are never touched. A destination
# that already exists is skipped, never overwritten, and reported.
# setup-python.sh calls this after installing, so installing this
# build organizes the mess left by earlier installs automatically.
organize_previous_versions() {
  local root="$1" moved=0 skipped=0 file rel base stamp dest destdir
  while IFS= read -r -d '' file; do
    rel="${file#$root/}"
    base="$(basename "$file")"
    stamp="${base##*.bak-}"
    case "$stamp" in
      [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]) ;;
      *) continue ;;
    esac
    dest="$root/previous-versions/$stamp/${rel%.bak-*}"
    if [ -e "$dest" ]; then
      printf 'organize: skipped %s (already in previous-versions/%s/)\n' "$rel" "$stamp"
      skipped=$((skipped + 1))
      continue
    fi
    destdir="$(dirname "$dest")"
    if ! mkdir -p "$destdir"; then
      printf 'organize: could not create %s\n' "$destdir"
      skipped=$((skipped + 1))
      continue
    fi
    if mv "$file" "$dest"; then
      printf 'organize: moved %s -> previous-versions/%s/%s\n' "$rel" "$stamp" "${rel%.bak-*}"
      moved=$((moved + 1))
    else
      printf 'organize: could not move %s\n' "$rel"
      skipped=$((skipped + 1))
    fi
  done < <(find "$root" -maxdepth 2 -type f -name '*.bak-????????-??????' -print0 2>/dev/null)
  printf 'organize: moved %s, skipped %s\n' "$moved" "$skipped"
  return 0
}

if [ "$CMD" = "organize" ]; then
  organize_previous_versions "$ROOT"
  exit 0
fi
# ---- end organize ------------------------------------------------------

# ---- backups (exp-2026-11-26.2) ------------------------------------------
# Read-only list of restore points, so a bad build can be undone
# without digging through $STATE by hand. `run.sh backups <playlist>`
# lists that playlist's main backup, its .prev, its .pre-undo and
# .fix-snapshot, and its per-run snapshots (newest first, 10 shown);
# `run.sh backups` with no playlist lists every backup-*.txt file in
# $STATE, newest first (20 shown). Each line names the file, its song
# count (one persistent ID per line), and its modified time. Prints
# plain lines to stdout and exits 0; it takes no lock, dumps nothing,
# and never touches a playlist, a setting, or a backup file. A missing
# main backup is reported as "none", not an error: undo already
# refuses on a missing backup, and this command is how the user finds
# which older file to feed `restore` instead. The per-playlist view
# resolves the file through backup_path_for, so a playlist name with
# spaces or slashes maps to the same sanitized file undo uses.
describe_backup_file() {
  local path="$1" label="$2" count when
  if [ ! -f "$path" ]; then
    printf '  %s: none\n' "$label"
    return 0
  fi
  count="$(grep -c . "$path" || true)"
  when="$(date -r "$path" '+%Y-%m-%d %H:%M' 2>/dev/null || echo unknown)"
  if [ "$count" = "1" ]; then
    printf '  %s: 1 song, %s, %s\n' "$label" "$when" "$path"
  else
    printf '  %s: %s songs, %s, %s\n' "$label" "$count" "$when" "$path"
  fi
  return 0
}

if [ "$CMD" = "backups" ]; then
  PLAYLIST="${2:-}"
  if [ -n "$PLAYLIST" ]; then
    BACKUP="$(backup_path_for "$PLAYLIST")"
    echo "backups for $PLAYLIST:"
    describe_backup_file "$BACKUP" "main"
    describe_backup_file "$BACKUP.prev" "previous"
    describe_backup_file "$BACKUP.pre-undo" "pre-undo snapshot"
    describe_backup_file "$BACKUP.fix-snapshot" "pre-restore snapshot"
    # Per-run snapshots, newest first. A glob loop collects them in
    # filename order (the run-<timestamp> names sort chronologically),
    # then the array is walked backwards, so no ls is needed: with
    # pipefail a failing ls would end the report early under set -e.
    snaps=()
    snap_count=0
    for snap in "$BACKUP".run-*.txt; do
      [ -f "$snap" ] || continue
      snaps+=("$snap")
      snap_count=$((snap_count + 1))
    done
    if [ "$snap_count" -eq 0 ]; then
      echo "  run snapshots: none"
    else
      shown=0
      for (( idx=snap_count - 1; idx >= 0; idx-- )); do
        if [ "$shown" -ge 10 ]; then break; fi
        describe_backup_file "${snaps[$idx]}" "run snapshot"
        shown=$((shown + 1))
      done
      if [ "$snap_count" -gt 10 ]; then
        echo "  ... and $((snap_count - 10)) older run snapshots"
      fi
    fi
  else
    echo "backups in $STATE:"
    # Newest first needs ls -t here (a glob loop cannot order by
    # time); the `|| true` keeps a no-match glob from ending the
    # report under set -e, and tool-created backup filenames never
    # contain whitespace, so line-based reads are safe.
    shown=0
    total=0
    while IFS= read -r file; do
      total=$((total + 1))
      if [ "$shown" -lt 20 ]; then
        describe_backup_file "$file" "$(basename "$file")"
        shown=$((shown + 1))
      fi
    done < <(ls -t "$STATE"/backup-*.txt 2>/dev/null || true)
    if [ "$total" -eq 0 ]; then
      echo "  none"
    elif [ "$total" -gt 20 ]; then
      echo "  ... and $((total - 20)) more"
    fi
  fi
  exit 0
fi
# ---- end backups -------------------------------------------------------

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
# ASCII banner (v3.0.11 exp 2026-11-21.1): printed at the top of
# the main menu each time it redraws, never in subcommand or log
# output. The art is Spencer's own: his "SeTeR" block in bold
# cyan, then his "SHUFFLE" block in bold italic magenta (the
# italic escape is \033[3m, closed with \033[23m), then a dim
# version line. The printf lines below were generated from his
# files, never retyped. Colors are empty when stdout is not a
# terminal, so piped output is plain ASCII art with no escape bytes.
print_banner() {
  printf '%s%s%s\n' "${C_BOLD_CYAN:-}" ' ▄█▀▀▀█▄█       ███▀▀██▀▀███       ▀███▀▀▀██▄' "${C_RESET:-}"
  printf '%s%s%s\n' "${C_BOLD_CYAN:-}" '▄██    ▀█       █▀   ██   ▀█         ██   ▀██▄' "${C_RESET:-}"
  printf '%s%s%s\n' "${C_BOLD_CYAN:-}" '▀███▄     ▄▄█▀██     ██      ▄▄█▀██  ██   ▄██' "${C_RESET:-}"
  printf '%s%s%s\n' "${C_BOLD_CYAN:-}" '  ▀█████▄▄█▀   ██    ██     ▄█▀   ██ ███████' "${C_RESET:-}"
  printf '%s%s%s\n' "${C_BOLD_CYAN:-}" '▄     ▀████▀▀▀▀▀▀    ██     ██▀▀▀▀▀▀ ██  ██▄' "${C_RESET:-}"
  printf '%s%s%s\n' "${C_BOLD_CYAN:-}" '██     ████▄    ▄    ██     ██▄    ▄ ██   ▀██▄' "${C_RESET:-}"
  printf '%s%s%s\n' "${C_BOLD_CYAN:-}" '█▀█████▀  ▀█████▀  ▄████▄    ▀█████▀████▄ ▄███▄' "${C_RESET:-}"
  printf '%s%s%s%s%s\n' "${C_BOLD_MAGENTA:-}" "${C_ITALIC:-}" '       ▄█▀▀▀█▄█████▀  ▀████▀▀███▀   ▀███▀███▀▀▀██████▀▀▀███████▀   ▀███▀▀▀███' "${C_ITALIC_OFF:-}" "${C_RESET:-}"
  printf '%s%s%s%s%s\n' "${C_BOLD_MAGENTA:-}" "${C_ITALIC:-}" '     ▄██    ▀█ ██      ██   ██       █   ██    ▀█ ██    ▀█ ██       ██    ▀█' "${C_ITALIC_OFF:-}" "${C_RESET:-}"
  printf '%s%s%s%s%s\n' "${C_BOLD_MAGENTA:-}" "${C_ITALIC:-}" '    ▀███▄     ██      ██   ██       █   ██   █   ██   █   ██       ██   █' "${C_ITALIC_OFF:-}" "${C_RESET:-}"
  printf '%s%s%s%s%s\n' "${C_BOLD_MAGENTA:-}" "${C_ITALIC:-}" '     ▀█████▄ ██████████   ██       █   ██▀▀██   ██▀▀██   ██       ██████' "${C_ITALIC_OFF:-}" "${C_RESET:-}"
  printf '%s%s%s%s%s\n' "${C_BOLD_MAGENTA:-}" "${C_ITALIC:-}" '  ▄     ▀██ ██      ██   ██       █   ██   █   ██   █   ██     ▄ ██   █  ▄' "${C_ITALIC_OFF:-}" "${C_RESET:-}"
  printf '%s%s%s%s%s\n' "${C_BOLD_MAGENTA:-}" "${C_ITALIC:-}" ' ██     ██ ██      ██   ██▄     ▄█   ██       ██       ██    ▄█ ██     ▄█' "${C_ITALIC_OFF:-}" "${C_RESET:-}"
  printf '%s%s%s%s%s\n' "${C_BOLD_MAGENTA:-}" "${C_ITALIC:-}" '█▀█████▀▄████▄  ▄████▄▄ ▀██████▀▀ ▄████▄   ▄████▄   ████████████████████' "${C_ITALIC_OFF:-}" "${C_RESET:-}"
  printf '%s%s%s\n' "${C_DIM:-}" 'v3.5' "${C_RESET:-}"
}

# Prompt, validate, and save one numeric Options value. $1 =
# prompt, $2 = low, $3 = high, $4 = display name, $5 = env
# marker var (OPTIONS_*_ENV_SET, recorded by
# load_persisted_options), $6 = env var name, $7 = validator
# function (options_validate_number or options_validate_blend),
# $8 = setter function, $9 = unit for the confirmation (may be
# empty). An env var set before this process started refuses
# the change with the plain message instead of pretending it
# took effect; a bad value prints a plain message and leaves
# the old value unchanged. Always returns 0: the submenu loop
# continues (an EOF read inside just falls through to the
# loop's own read, which exits).
menu_options_set_value() {
  local prompt="$1" lo="$2" hi="$3" name="$4" marker="$5" env_name="$6" validator="$7" setter="$8" unit="${9:-}"
  local new_val valid_rc
  if [ -n "${!marker:-}" ]; then
    printf '%s is set by %s=%s in the environment; unset it to use the menu setting.\n' "$name" "$env_name" "${!env_name:-}"
    return 0
  fi
  printf '%s' "$prompt"
  read -r new_val || return 0
  new_val="$("$validator" "$new_val" "$lo" "$hi")"
  valid_rc=$?
  if [ "$valid_rc" -eq 0 ]; then
    if "$setter" "$new_val"; then
      if [ -n "$unit" ]; then
        printf '%s is now %s %s.\n' "$name" "$new_val" "$unit"
      else
        printf '%s is now %s.\n' "$name" "$new_val"
      fi
    else
      printf 'could not save %s; unchanged.\n' "$name"
    fi
  elif [ "$valid_rc" -eq 2 ]; then
    printf 'not a number %s-%s; %s unchanged.\n' "$lo" "$hi" "$name"
  else
    printf '%s must be %s-%s; %s unchanged.\n' "$name" "$lo" "$hi" "$name"
  fi
  return 0
}

menu_options() {
  local choice ai_state split_state featuring_state dedupe_state
  local ai_blend ai_mood_cost flow_size flow_pool flow_source flow_target
  local artist_spacing rediscover_size rediscover_max_per_artist
  local rediscover_cooldown rediscover_stale probe_age
  local new_val valid_rc env_note flow_source_note flow_target_note picked_lower
  local blend_note mood_note size_note pool_note spacing_note
  local red_size_note red_max_note red_cool_note red_stale_note
  local feat_note dedupe_note
  while true; do
    if options_ai_on; then ai_state="${C_BOLD_GREEN:-}ON${C_RESET:-}"; else ai_state="${C_DIM:-}OFF${C_RESET:-}"; fi
    if options_split_collabs_on; then split_state="${C_BOLD_GREEN:-}ON${C_RESET:-}"; else split_state="${C_DIM:-}OFF${C_RESET:-}"; fi
    if options_featuring_on; then featuring_state="${C_BOLD_GREEN:-}ON${C_RESET:-}"; else featuring_state="${C_DIM:-}OFF${C_RESET:-}"; fi
    dedupe_state="$(options_dedupe_match)"
    ai_blend="$(options_ai_blend)"
    ai_mood_cost="$(options_ai_mood_cost)"
    flow_size="$(options_flow_size)"
    flow_pool="$(options_flow_pool_max)"
    flow_source="$(options_flow_source)"
    if [ "$flow_source" = "library" ]; then
      flow_source="Whole library"
    fi
    flow_target="$(options_flow_target)"
    artist_spacing="$(options_artist_spacing)"
    rediscover_size="$(options_rediscover_size)"
    rediscover_max_per_artist="$(options_rediscover_max_per_artist)"
    rediscover_cooldown="$(options_rediscover_cooldown_days)"
    rediscover_stale="$(options_rediscover_stale_days)"
    probe_age="$(options_probe_max_age)"
    env_note=""
    if [ -n "${SETER_PROBE_MAX_AGE_HOURS:-}" ]; then
      env_note="${C_DIM_YELLOW:-} (SETER_PROBE_MAX_AGE_HOURS=$SETER_PROBE_MAX_AGE_HOURS is set in this shell; the daily run uses that instead)${C_RESET:-}"
    fi
    flow_source_note=""
    if [ -n "${OPTIONS_FLOW_SOURCE_ENV_SET:-}" ]; then
      flow_source_note="${C_DIM_YELLOW:-} (SETER_FLOW_SOURCE=$SETER_FLOW_SOURCE is set in this shell; the menu setting is ignored)${C_RESET:-}"
    fi
    flow_target_note=""
    if [ -n "${OPTIONS_FLOW_TARGET_ENV_SET:-}" ]; then
      flow_target_note="${C_DIM_YELLOW:-} (SETER_FLOW_TARGET=$SETER_FLOW_TARGET is set in this shell; the menu setting is ignored)${C_RESET:-}"
    fi
    blend_note="$(options_env_note SETER_AI_BLEND OPTIONS_AI_BLEND_ENV_SET)"
    mood_note="$(options_env_note SETER_AI_MOOD_COST OPTIONS_AI_MOOD_COST_ENV_SET)"
    size_note="$(options_env_note SETER_FLOW_SIZE OPTIONS_FLOW_SIZE_ENV_SET)"
    pool_note="$(options_env_note SETER_FLOW_POOL_MAX OPTIONS_FLOW_POOL_MAX_ENV_SET)"
    spacing_note="$(options_env_note SETER_ARTIST_SPACING OPTIONS_ARTIST_SPACING_ENV_SET)"
    red_size_note="$(options_env_note SETER_REDISCOVER_SIZE OPTIONS_REDISCOVER_SIZE_ENV_SET)"
    red_max_note="$(options_env_note SETER_REDISCOVER_MAX_PER_ARTIST OPTIONS_REDISCOVER_MAX_PER_ARTIST_ENV_SET)"
    red_cool_note="$(options_env_note SETER_REDISCOVER_COOLDOWN_DAYS OPTIONS_REDISCOVER_COOLDOWN_DAYS_ENV_SET)"
    red_stale_note="$(options_env_note SETER_REDISCOVER_STALE_DAYS OPTIONS_REDISCOVER_STALE_DAYS_ENV_SET)"
    feat_note="$(options_env_note SETER_FEATURING_SAME_ARTIST OPTIONS_FEATURING_ENV_SET)"
    dedupe_note="$(options_env_note SETER_DEDUPE_MATCH OPTIONS_DEDUPE_ENV_SET)"
    printf '\n%s\n' "${C_BOLD:-}Options${C_RESET:-}"
    printf '%s\n' "${C_BOLD:-}  AI + Flow${C_RESET:-}"
    printf '  AI tagging for Flow: %s\n' "$ai_state"
    printf '  AI blend: %s%s%s (0-1)%s\n' "${C_CYAN:-}" "$ai_blend" "${C_RESET:-}" "$blend_note"
    printf '  AI mood cost: %s%s%s (0-10, 0 = moods do not steer Flow)%s\n' "${C_CYAN:-}" "$ai_mood_cost" "${C_RESET:-}" "$mood_note"
    printf '  Flow size: %s%s%s songs (10-200)%s\n' "${C_CYAN:-}" "$flow_size" "${C_RESET:-}" "$size_note"
    printf '  Flow pool: %s%s%s songs (0-1000, 0 = no cap)%s\n' "${C_CYAN:-}" "$flow_pool" "${C_RESET:-}" "$pool_note"
    printf '  Flow source: %s%s\n' "$flow_source" "$flow_source_note"
    printf '  Flow target: %s%s\n' "$flow_target" "$flow_target_note"
    printf '%s\n' "${C_BOLD:-}  Shuffle${C_RESET:-}"
    printf '  Artist spacing: %s%s%s (1-5, 1 = just not back-to-back)%s\n' "${C_CYAN:-}" "$artist_spacing" "${C_RESET:-}" "$spacing_note"
    printf '  Split collabs: %s\n' "$split_state"
    printf '  "Feat." counts as same artist: %s%s\n' "$featuring_state" "$feat_note"
    printf '%s\n' "${C_BOLD:-}  Rediscover${C_RESET:-}"
    printf '  Size: %s%s%s songs (5-500)%s\n' "${C_CYAN:-}" "$rediscover_size" "${C_RESET:-}" "$red_size_note"
    printf '  Max per artist: %s%s%s (0-10, 0 = no limit)%s\n' "${C_CYAN:-}" "$rediscover_max_per_artist" "${C_RESET:-}" "$red_max_note"
    printf '  Cooldown: %s%s%s days (0-90, 0 = off)%s\n' "${C_CYAN:-}" "$rediscover_cooldown" "${C_RESET:-}" "$red_cool_note"
    printf '  Stale after: %s%s%s days (7-365)%s\n' "${C_CYAN:-}" "$rediscover_stale" "${C_RESET:-}" "$red_stale_note"
    printf '%s\n' "${C_BOLD:-}  Dedupe + probes${C_RESET:-}"
    printf '  Dedupe match: %s%s%s (song = artist + title; id = track ID only)%s\n' "${C_CYAN:-}" "$dedupe_state" "${C_RESET:-}" "$dedupe_note"
    printf '  Probe max age: %s%s%s hours (0-40, 0 = probe every day)%s\n' "${C_CYAN:-}" "$probe_age" "${C_RESET:-}" "$env_note"
    printf '  (AI tagging needs sudo fm license once + ai-selftest before Flow uses it.)\n'
    printf '\n%s\n' "${C_BOLD_CYAN:-}  1) Toggle AI tagging${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  2) Set AI blend (0.0-1.0)${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  3) Set AI mood cost (0-10)${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  4) Set Flow size (10-200 songs)${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  5) Set Flow pool (0-1000, 0 = no cap)${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  6) Set Flow source playlist${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  7) Set Flow target playlist${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  8) Set artist spacing (1-5)${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  9) Toggle split collabs${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  10) Toggle \"feat.\" counts as same artist${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  11) Set Rediscover size (5-500 songs)${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  12) Set max per artist (0-10, 0 = no limit)${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  13) Set Rediscover cooldown (0-90 days, 0 = off)${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  14) Set stale after (7-365 days)${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  15) Set probe max age (0-40 hours)${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  16) Toggle dedupe match (song/id)${C_RESET:-}"
    printf '%s\n' "${C_BOLD_CYAN:-}  0) Back${C_RESET:-}"
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
        menu_options_set_value 'AI blend (0.0-1.0): ' 0.0 1.0 'AI blend' OPTIONS_AI_BLEND_ENV_SET SETER_AI_BLEND options_validate_blend options_set_ai_blend
        ;;
      3)
        menu_options_set_value 'AI mood cost (0-10, 0 = moods do not steer Flow): ' 0 10 'AI mood cost' OPTIONS_AI_MOOD_COST_ENV_SET SETER_AI_MOOD_COST options_validate_number options_set_ai_mood_cost
        ;;
      4)
        menu_options_set_value 'Flow size in songs (10-200): ' 10 200 'Flow size' OPTIONS_FLOW_SIZE_ENV_SET SETER_FLOW_SIZE options_validate_number options_set_flow_size songs
        ;;
      5)
        menu_options_set_value 'Flow pool cap in songs (0-1000, 0 = no cap): ' 0 1000 'Flow pool' OPTIONS_FLOW_POOL_MAX_ENV_SET SETER_FLOW_POOL_MAX options_validate_number options_set_flow_pool_max songs
        ;;
      6)
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
      7)
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
      8)
        menu_options_set_value 'Artist spacing (1-5, 1 = just not back-to-back): ' 1 5 'Artist spacing' OPTIONS_ARTIST_SPACING_ENV_SET SETER_ARTIST_SPACING options_validate_number options_set_artist_spacing
        ;;
      9)
        if [ -n "${OPTIONS_SPLIT_ENV_SET:-}" ]; then
          echo "Split collabs is set by SETER_SPLIT_COLLABS=$SETER_SPLIT_COLLABS in the environment; unset it to use the menu setting."
        elif options_split_collabs_on; then
          options_set_split_collabs off && echo "Split collabs is now OFF."
        else
          options_set_split_collabs on && echo "Split collabs is now ON: \"A & B\" counts as artist \"A\" for spacing and caps."
        fi
        ;;
      10)
        if [ -n "${OPTIONS_FEATURING_ENV_SET:-}" ]; then
          echo "\"Feat.\" counts as same artist is set by SETER_FEATURING_SAME_ARTIST=$SETER_FEATURING_SAME_ARTIST in the environment; unset it to use the menu setting."
        elif options_featuring_on; then
          options_set_featuring 0 && echo '"Feat." counts as same artist is now OFF.'
        else
          options_set_featuring 1 && echo '"Feat." counts as same artist is now ON.'
        fi
        ;;
      11)
        menu_options_set_value 'Rediscover size in songs (5-500): ' 5 500 'Rediscover size' OPTIONS_REDISCOVER_SIZE_ENV_SET SETER_REDISCOVER_SIZE options_validate_number options_set_rediscover_size songs
        ;;
      12)
        menu_options_set_value 'Max per artist (0-10, 0 = no limit): ' 0 10 'Max per artist' OPTIONS_REDISCOVER_MAX_PER_ARTIST_ENV_SET SETER_REDISCOVER_MAX_PER_ARTIST options_validate_number options_set_rediscover_max_per_artist
        ;;
      13)
        menu_options_set_value 'Rediscover cooldown in days (0-90, 0 = off): ' 0 90 'Rediscover cooldown' OPTIONS_REDISCOVER_COOLDOWN_DAYS_ENV_SET SETER_REDISCOVER_COOLDOWN_DAYS options_validate_number options_set_rediscover_cooldown_days days
        ;;
      14)
        menu_options_set_value 'Stale after in days (7-365): ' 7 365 'Stale after' OPTIONS_REDISCOVER_STALE_DAYS_ENV_SET SETER_REDISCOVER_STALE_DAYS options_validate_number options_set_rediscover_stale_days days
        ;;
      15)
        printf 'Probe max age in hours (0-40, 0 = probe every day): '
        read -r new_val || return 0
        new_val="$(options_validate_number "$new_val" 0 40)"
        valid_rc=$?
        if [ "$valid_rc" -eq 0 ]; then
          if options_write_probe_max_age "$new_val"; then
            echo "Probe max age is now $new_val hours."
          else
            echo "could not save probe max age; unchanged."
          fi
        elif [ "$valid_rc" -eq 2 ]; then
          echo "not a number 0-40; probe max age unchanged."
        else
          echo "probe max age must be 0-40; probe max age unchanged."
        fi
        ;;
      16)
        if [ -n "${OPTIONS_DEDUPE_ENV_SET:-}" ]; then
          echo "Dedupe match is set by SETER_DEDUPE_MATCH=$SETER_DEDUPE_MATCH in the environment; unset it to use the menu setting."
        elif [ "$(options_dedupe_match)" = "song" ]; then
          options_set_dedupe_match id && echo "Dedupe match is now id (same track ID only)."
        else
          options_set_dedupe_match song && echo "Dedupe match is now song (same artist + title)."
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
    print_banner
    printf '\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
      "${C_BOLD:-}SeTeR Shuffle${C_RESET:-}" \
      "${C_BOLD_CYAN:-}  1) Shuffle a playlist${C_RESET:-}" \
      "${C_BOLD_CYAN:-}  2) Rediscover${C_RESET:-}" \
      "${C_BOLD_CYAN:-}  3) Remove duplicates (dedupe)${C_RESET:-}" \
      "${C_BOLD_CYAN:-}  4) Undo last shuffle${C_RESET:-}" \
      "${C_BOLD_CYAN:-}  5) Flow${C_RESET:-}" \
      "${C_BOLD_CYAN:-}  6) Flow preview${C_RESET:-}" \
      "${C_BOLD_CYAN:-}  7) Audit${C_RESET:-}" \
      "${C_BOLD_CYAN:-}  8) Options${C_RESET:-}" \
      "${C_BOLD_CYAN:-}  0) Quit${C_RESET:-}"
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
