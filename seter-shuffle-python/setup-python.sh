#!/bin/bash
# setup-python.sh (SeTeR Shuffle, Python build, proposed stable v3.0)
#
# Installs the Python build for macOS. This is stable-preparation
# work on the experimental branch: it does NOT publish a stable
# release, does NOT create a tag, and does NOT merge anything to
# main. The version name below is the PROPOSED stable name (v3.0);
# the installer records it as "3.0-proposed" until Spencer approves
# the exact stable change list, at which point a real stable
# publish is a separate, explicit step.
#
# What it installs, and what it deliberately does NOT touch:
# - Copies run.sh, check-python.sh, daily.sh, migrate-to-python.sh,
#   bridge/*.applescript, and seter_shuffle/*.py from this folder
#   (local files only; nothing is downloaded) into a NEW install
#   directory, by default ~/Documents/SeTeRShufflePython.
# - Writes a launchd plist for the daily run under a NEW label,
#   com.seter.python.daily, at the daily hour below.
# - NEVER touches the v2.6 install (~/Documents/SeTeRShuffle), its
#   scripts, its backups, or its launchd job (com.seter.daily).
#   Disabling the v2.6 job is a separate, explicit migration step
#   (migrate-to-python.sh --confirm); this installer does not do it.
# - NEVER touches Rediscover history
#   (~/Documents/SeTeRShuffle/rediscover-history.tsv): the Python
#   run reads that same file, so history carries over without a copy.
# - NEVER touches any playlist in Music.
#
# Idempotency and version refusal:
# - Re-running with the same version re-copies the same files
#   (differing files get a timestamped .bak copy first) and
#   re-writes the same plist: safe to re-run.
# - If the install directory already holds a DIFFERENT version
#   marker, the installer REFUSES unless --force is given, so an
#   unrelated install is never silently overwritten.
#
# Usage:
#   bash setup-python.sh [--playlist NAME] [--hour H] [--minute M]
#                        [--no-daily] [--force] [-y|--yes]
#                        [--uninstall] [-h|--help]
#
# Test hooks (unit tests only, never used by a real install):
#   SETER_TEST_MODE=1          skip the macOS-only checks
#                              (uname, osascript, launchctl)
#   SETER_PYTHON_INSTALL_DIR   override the install directory
#   SETER_LAUNCHAGENTS_DIR     override the LaunchAgents directory
#   SETER_STATE_DIR            override the log/state directory
#                              used for the plist log paths

set -euo pipefail

# ---------------------------------------------------------------------------
# THE DAILY SCHEDULE, IN ONE PLACE. Change the hour here (and only
# here) to move the daily run; the plist is generated from these
# variables, so there is no second copy of the time to drift.
# Proposed daily time, matching v2.6's 8:00 AM run:
# ---------------------------------------------------------------------------
DAILY_HOUR=8
DAILY_MINUTE=0
DAILY_PLAYLIST_DEFAULT="My New Sandwich Recipe"
PROPOSED_VERSION="3.0"
VERSION_MARKER="3.0-proposed"
PLIST_LABEL="com.seter.python.daily"

INSTALL_DIR="${SETER_PYTHON_INSTALL_DIR:-$HOME/Documents/SeTeRShufflePython}"
PLIST_DIR="${SETER_LAUNCHAGENTS_DIR:-$HOME/Library/LaunchAgents}"
PLIST_PATH="$PLIST_DIR/$PLIST_LABEL.plist"
LOG_DIR="${SETER_STATE_DIR:-$HOME/Library/Logs/seter-shuffle-python}"
LOG_FILE="$LOG_DIR/daily.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

PLAYLIST=""
HOUR=""
MINUTE=""
NO_DAILY=0
FORCE=0
ASSUME_YES=0
UNINSTALL=0

usage() {
  cat <<'EOF'
SeTeR Shuffle (Python) setup -- proposed stable v3.0, experimental prep

Usage: bash setup-python.sh [options]

  --playlist NAME   playlist the daily run shuffles (default: My New Sandwich Recipe)
  --hour H          hour of the day (0-23) for the daily run (default 8)
  --minute M        minute of the hour (0-59) for the daily run (default 0)
  --no-daily        install only, no schedule
  --force           allow replacing a different installed version
  -y, --yes         don't ask questions; use the options given and defaults
  --uninstall       remove the Python schedule and install directory
                    (backups, logs, and Rediscover history are kept)
  -h, --help        show this help

This installer never touches the v2.6 install or its daily job.
To switch the daily run from v2.6 to this build, run
migrate-to-python.sh --confirm as a separate, explicit step.
EOF
}

say() { printf '%s\n' "$*"; }
ok() { printf '  ok %s\n' "$*"; }
warn() { printf '  ! %s\n' >&2; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --playlist) [ $# -ge 2 ] || die "--playlist needs a playlist name"; PLAYLIST="$2"; shift 2 ;;
    --playlist=*) PLAYLIST="${1#*=}"; shift ;;
    --hour) [ $# -ge 2 ] || die "--hour needs a number from 0 to 23"; HOUR="$2"; shift 2 ;;
    --hour=*) HOUR="${1#*=}"; shift ;;
    --minute) [ $# -ge 2 ] || die "--minute needs a number from 0 to 59"; MINUTE="$2"; shift 2 ;;
    --minute=*) MINUTE="${1#*=}"; shift ;;
    --no-daily) NO_DAILY=1; shift ;;
    --force) FORCE=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

if [ -z "$HOUR" ]; then HOUR="$DAILY_HOUR"; fi
if [ -z "$MINUTE" ]; then MINUTE="$DAILY_MINUTE"; fi
if [ -z "$PLAYLIST" ]; then PLAYLIST="$DAILY_PLAYLIST_DEFAULT"; fi
case "$HOUR" in ''|*[!0-9]*) die "--hour must be a number from 0 to 23" ;; esac
[ "$HOUR" -ge 0 ] && [ "$HOUR" -le 23 ] || die "--hour must be a number from 0 to 23"
case "$MINUTE" in ''|*[!0-9]*) die "--minute must be a number from 0 to 59" ;; esac
[ "$MINUTE" -ge 0 ] && [ "$MINUTE" -le 59 ] || die "--minute must be a number from 0 to 59"
xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

launchd_unload() {
  if [ -n "${SETER_TEST_MODE:-}" ]; then return 0; fi
  local uid
  uid="$(id -u)"
  launchctl bootout "gui/$uid" "$PLIST_PATH" >/dev/null 2>&1 || launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
}

launchd_load() {
  if [ -n "${SETER_TEST_MODE:-}" ]; then return 0; fi
  local uid
  uid="$(id -u)"
  launchd_unload
  if launchctl bootstrap "gui/$uid" "$PLIST_PATH" >/dev/null 2>&1; then return 0; fi
  launchctl load "$PLIST_PATH"
}

write_plist() {
  local playlist="$1" hour="$2" minute="$3"
  mkdir -p "$PLIST_DIR" "$LOG_DIR"
  cat >"$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$PLIST_LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>$(xml_escape "$INSTALL_DIR/daily.sh")</string>
		<string>$(xml_escape "$playlist")</string>
	</array>
	<key>StartCalendarInterval</key>
	<dict>
		<key>Hour</key>
		<integer>$hour</integer>
		<key>Minute</key>
		<integer>$minute</integer>
	</dict>
	<key>StandardOutPath</key>
	<string>$(xml_escape "$LOG_FILE")</string>
	<key>StandardErrorPath</key>
	<string>$(xml_escape "$LOG_FILE")</string>
</dict>
</plist>
EOF
}

do_uninstall() {
  say "Removing the SeTeR Shuffle (Python) install..."
  if [ -f "$PLIST_PATH" ]; then
    launchd_unload
    rm -f "$PLIST_PATH"
    ok "removed the Python daily schedule ($PLIST_LABEL)"
  fi
  if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    ok "removed $INSTALL_DIR"
  fi
  say "Kept (never deleted by uninstall): backups, logs, Rediscover history, and the entire v2.6 install and its daily job."
  say "Done. Your playlists in Music were left alone."
}

# macOS-only checks, skipped only in test mode.
if [ -z "${SETER_TEST_MODE:-}" ]; then
  [ "$(uname -s)" = "Darwin" ] || die "SeTeR Shuffle (Python) drives the Music app, so it only runs on macOS."
  for tool in osascript launchctl; do
    command -v "$tool" >/dev/null 2>&1 || die "Missing '$tool', which ships with macOS."
  done
fi

if [ "$UNINSTALL" = 1 ]; then
  do_uninstall
  exit 0
fi

# A real python3, before anything is installed: the daily run is
# useless without one, and finding out after install wastes a day.
if [ -z "${SETER_TEST_MODE:-}" ]; then
  bash "$SCRIPT_DIR/check-python.sh" >/dev/null || die "No usable python3 (3.9+) found; install real Python first, then re-run setup."
fi

say "SeTeR Shuffle (Python) setup -- proposed stable $PROPOSED_VERSION (prep build, not a stable release)"
say ""

# Version refusal: an existing install with a different marker is
# never silently overwritten.
MARKER_FILE="$INSTALL_DIR/installed-version.txt"
if [ -f "$MARKER_FILE" ]; then
  EXISTING="$(cat "$MARKER_FILE" 2>/dev/null || true)"
  if [ "$EXISTING" != "$VERSION_MARKER" ] && [ "$FORCE" != 1 ]; then
    die "Install directory $INSTALL_DIR already holds version '$EXISTING' (this installer is '$VERSION_MARKER'). Re-run with --force to replace it, or choose another directory with SETER_PYTHON_INSTALL_DIR."
  fi
fi

say "1. Installing into $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bridge" "$INSTALL_DIR/seter_shuffle"
install_file() {
  local src="$1" dest="$2"
  [ -f "$src" ] || die "Missing source file: $src (run setup from the unzipped build folder)"
  if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
    local backup
    backup="$dest.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$dest" "$backup"
    ok "kept your previous $(basename "$dest") as $(basename "$backup")"
  fi
  cp "$src" "$dest"
}
install_file "$SCRIPT_DIR/run.sh" "$INSTALL_DIR/run.sh"
install_file "$SCRIPT_DIR/check-python.sh" "$INSTALL_DIR/check-python.sh"
install_file "$SCRIPT_DIR/daily.sh" "$INSTALL_DIR/daily.sh"
install_file "$SCRIPT_DIR/setup-python.sh" "$INSTALL_DIR/setup-python.sh"
install_file "$SCRIPT_DIR/migrate-to-python.sh" "$INSTALL_DIR/migrate-to-python.sh"
for f in "$SCRIPT_DIR"/bridge/*.applescript; do
  install_file "$f" "$INSTALL_DIR/bridge/$(basename "$f")"
done
for f in "$SCRIPT_DIR"/seter_shuffle/*.py; do
  install_file "$f" "$INSTALL_DIR/seter_shuffle/$(basename "$f")"
done
chmod +x "$INSTALL_DIR/run.sh" "$INSTALL_DIR/check-python.sh" "$INSTALL_DIR/daily.sh" "$INSTALL_DIR/setup-python.sh" "$INSTALL_DIR/migrate-to-python.sh"
printf '%s\n' "$VERSION_MARKER" > "$MARKER_FILE"
ok "installed the Python build ($VERSION_MARKER)"

if [ "$NO_DAILY" = 1 ]; then
  say "2. Daily run: skipped (--no-daily)"
else
  say "2. Scheduling the daily run at $HOUR:$(printf '%02d' "$MINUTE") for playlist \"$PLAYLIST\""
  write_plist "$PLAYLIST" "$HOUR" "$MINUTE"
  if launchd_load; then
    ok "scheduled as $PLIST_LABEL (if your Mac is asleep then, it runs when it wakes)"
  else
    warn "Couldn't load the schedule. Try: launchctl load \"$PLIST_PATH\""
  fi
  say "   NOTE: the daily run refuses without a fresh (<24h) per-target mapping for both"
  say "   \"$PLAYLIST\" and \"SeTeR Rediscover\". Run sortprobe by hand for each target"
  say "   before the first scheduled run, and again whenever a mapping goes stale."
  say "   The daily run never auto-probes and never borrows another target's mapping."
fi

say ""
say "All set (prep install; not a stable release)."
say "  Install:   $INSTALL_DIR"
say "  Daily log: $LOG_FILE"
say "  Manual:    cd $INSTALL_DIR && ./run.sh audit"
say "  v2.6 untouched: its install and its com.seter.daily job are still in place."
say "  To switch the daily run to this build: bash $INSTALL_DIR/migrate-to-python.sh --confirm"
say "  To remove this build: bash setup-python.sh --uninstall"
