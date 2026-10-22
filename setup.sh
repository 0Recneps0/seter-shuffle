#!/bin/bash
# SeTeR Shuffle setup: installs the scripts, builds double-clickable apps and
# (optionally) schedules the daily shuffle + Rediscover refresh. macOS only.
# Safe to re-run: it keeps a timestamped copy of anything it replaces.
#
#   bash setup.sh                       interactive (recommended)
#   bash setup.sh --playlist "My Mix"   schedule the daily run for that playlist
#   bash setup.sh --no-daily            install only, no schedule
#   bash setup.sh --uninstall           remove what setup installed
#   bash setup.sh --help
#
# Run from a clone of the repo, or straight from GitHub:
#   bash <(curl -fsSL https://raw.githubusercontent.com/0Recneps0/seter-shuffle/main/setup.sh)

set -euo pipefail

RAW_URL="${SETER_RAW_URL:-https://raw.githubusercontent.com/0Recneps0/seter-shuffle/main}"
INSTALL_DIR="$HOME/Documents/SeTeRShuffle"
APP_DIR="$HOME/Applications"
MAIN="SeTeR-shuffle.applescript"
WRAP="SeTeR-sandwich-shuffle.applescript"
MAIN_APP="SeTeR Shuffle.app"
WRAP_APP="SeTeR Sandwich Shuffle.app"
PLIST_LABEL="com.seter.daily"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
LOG_FILE="$HOME/Library/Logs/seter-shuffle.log"
AUTHOR_DEFAULT_PLAYLIST="my new sandwich recipe" # placeholder shipped in the scripts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

PLAYLIST=""
HOUR=""
NO_DAILY=0
NO_APPS=0
NO_PREVIEW=0
ASSUME_YES=0
UNINSTALL=0
WORK=""

usage() {
  cat <<'EOF'
SeTeR Shuffle setup

Usage: bash setup.sh [options]

  --playlist NAME   playlist the daily run shuffles (must already exist in Music)
  --hour H          hour of the day (0-23) for the daily run (default 8)
  --no-daily        don't schedule the daily run
  --no-apps         don't build the double-clickable apps
  --no-preview      skip the read-only Rediscover preview at the end
  -y, --yes         don't ask questions; use the options given and defaults
  --uninstall       remove the apps, schedule and installed scripts
  -h, --help        show this help
EOF
}

say() { printf '%s\n' "$*"; }
ok() { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [ -n "$WORK" ]; then rm -rf "$WORK" 2>/dev/null || true; fi
}
trap cleanup EXIT

# One scratch directory for everything temporary; removed on exit.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/seter-setup.XXXXXX")"
new_tmp() { mktemp "$WORK/f.XXXXXX"; }

# ---------------------------------------------------------------------------
# prompts (read from the terminal even when the script itself is piped in)
# ---------------------------------------------------------------------------

have_tty() { (exec </dev/tty) 2>/dev/null; }

# ask "prompt" "default"  -> answer in $REPLY
ask() {
  local prompt="$1" default="${2:-}"
  REPLY="$default"
  if [ "$ASSUME_YES" = 1 ] || ! have_tty; then return 0; fi
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$prompt" "$default" >/dev/tty
  else
    printf '%s: ' "$prompt" >/dev/tty
  fi
  IFS= read -r REPLY </dev/tty || REPLY=""
  if [ -z "$REPLY" ]; then REPLY="$default"; fi
}

# confirm "question" y|n  -> exit status 0 for yes
confirm() {
  ask "$1 (y/n)" "${2:-y}"
  case "$REPLY" in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# arguments
# ---------------------------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --playlist)
      [ $# -ge 2 ] || die "--playlist needs a playlist name"
      PLAYLIST="$2"
      shift 2
      ;;
    --playlist=*)
      PLAYLIST="${1#*=}"
      shift
      ;;
    --hour)
      [ $# -ge 2 ] || die "--hour needs a number from 0 to 23"
      HOUR="$2"
      shift 2
      ;;
    --hour=*)
      HOUR="${1#*=}"
      shift
      ;;
    --no-daily)
      NO_DAILY=1
      shift
      ;;
    --no-apps)
      NO_APPS=1
      shift
      ;;
    --no-preview)
      NO_PREVIEW=1
      shift
      ;;
    -y | --yes)
      ASSUME_YES=1
      shift
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

if [ -n "$HOUR" ]; then
  case "$HOUR" in
    '' | *[!0-9]*) die "--hour must be a number from 0 to 23" ;;
  esac
  [ "$HOUR" -ge 0 ] && [ "$HOUR" -le 23 ] || die "--hour must be a number from 0 to 23"
fi
if [ "$NO_DAILY" = 1 ] && [ -n "$PLAYLIST" ]; then
  die "--no-daily and --playlist can't be used together"
fi

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Copies a repo file (or downloads it when setup.sh was run on its own).
fetch_file() {
  local name="$1" dest="$2"
  if [ -f "$SCRIPT_DIR/$name" ]; then
    cp "$SCRIPT_DIR/$name" "$dest"
  else
    curl -fsSL "$RAW_URL/$name" -o "$dest" || die "Couldn't download $name from $RAW_URL"
  fi
}

# Installs a script into INSTALL_DIR, keeping a timestamped copy of any
# different version it replaces (your edited settings are in that copy).
install_script() {
  local name="$1" dest="$INSTALL_DIR/$1" tmp
  tmp="$(new_tmp)"
  fetch_file "$name" "$tmp"
  if [ -f "$dest" ] && ! cmp -s "$tmp" "$dest"; then
    local backup
    backup="$dest.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$dest" "$backup"
    ok "kept your previous $name as $(basename "$backup")"
  fi
  cp "$tmp" "$dest"
  chmod 644 "$dest"
}

# Sets `property NAME : "value"` in an AppleScript file, escaping the value.
set_string_property() {
  local file="$1" prop="$2" value="$3"
  PL_VALUE="$value" perl -pi -e '
    BEGIN { ($v = $ENV{PL_VALUE}) =~ s/\\/\\\\/g; $v =~ s/"/\\"/g; }
    s/^(property '"$prop"' : )"(?:[^"\\]|\\.)*"/$1"$v"/;
  ' "$file"
  grep -q "^property $prop : " "$file" || die "Couldn't find the $prop setting in $(basename "$file")"
}

# The daily playlist saved by an earlier setup run (blank if never customized).
current_playlist() {
  local f="$INSTALL_DIR/$MAIN" v=""
  if [ -f "$f" ]; then
    v="$(sed -n 's/^property defaultDailyPlaylist : "\(.*\)" *--.*/\1/p' "$f" | head -n 1)"
    [ -n "$v" ] || v="$(sed -n 's/^property defaultDailyPlaylist : "\(.*\)"$/\1/p' "$f" | head -n 1)"
  fi
  v="$(printf '%s' "$v" | sed -e 's/\\"/"/g' -e 's/\\\\/\\/g')"
  if [ "$v" = "$AUTHOR_DEFAULT_PLAYLIST" ]; then v=""; fi
  printf '%s' "$v"
}

# One regular (non-smart) playlist name per line. Also triggers the macOS
# "allow control of Music" prompt, which is the best time for it.
list_playlists() {
  osascript <<'OSA'
tell application "Music"
	set nms to name of every user playlist whose smart is false
end tell
set AppleScript's text item delimiters to linefeed
return nms as text
OSA
}

launchd_unload() {
  local uid
  uid="$(id -u)"
  launchctl bootout "gui/$uid" "$PLIST_PATH" >/dev/null 2>&1 || launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
}

launchd_load() {
  local uid
  uid="$(id -u)"
  launchd_unload
  if launchctl bootstrap "gui/$uid" "$PLIST_PATH" >/dev/null 2>&1; then return 0; fi
  launchctl load "$PLIST_PATH"
}

write_plist() {
  local playlist="$1" hour="$2"
  mkdir -p "$(dirname "$PLIST_PATH")" "$(dirname "$LOG_FILE")"
  cat >"$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$PLIST_LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/osascript</string>
		<string>$(xml_escape "$INSTALL_DIR/$MAIN")</string>
		<string>daily</string>
		<string>$(xml_escape "$playlist")</string>
	</array>
	<key>StartCalendarInterval</key>
	<dict>
		<key>Hour</key>
		<integer>$hour</integer>
		<key>Minute</key>
		<integer>0</integer>
	</dict>
	<key>StandardOutPath</key>
	<string>$(xml_escape "$LOG_FILE")</string>
	<key>StandardErrorPath</key>
	<string>$(xml_escape "$LOG_FILE")</string>
</dict>
</plist>
EOF
}

build_app() {
  local src="$1" app="$2"
  mkdir -p "$APP_DIR"
  rm -rf "${APP_DIR:?}/$app"
  osacompile -o "$APP_DIR/$app" "$src" || die "Couldn't build $app"
}

# ---------------------------------------------------------------------------
# uninstall
# ---------------------------------------------------------------------------

do_uninstall() {
  say "Removing SeTeR Shuffle..."
  if [ -f "$PLIST_PATH" ]; then
    launchd_unload
    rm -f "$PLIST_PATH"
    ok "removed the daily schedule"
  fi
  rm -rf "${APP_DIR:?}/$MAIN_APP" "${APP_DIR:?}/$WRAP_APP"
  rm -f "$INSTALL_DIR/$MAIN" "$INSTALL_DIR/$WRAP" "$INSTALL_DIR"/"$MAIN".bak-* "$INSTALL_DIR"/"$WRAP".bak-*
  ok "removed the apps and scripts"
  if [ -d "$INSTALL_DIR/backups" ] || [ -f "$INSTALL_DIR/rediscover-history.tsv" ]; then
    if confirm "Also delete your library backups and Rediscover history in $INSTALL_DIR?" n; then
      rm -rf "$INSTALL_DIR"
      ok "removed $INSTALL_DIR"
    else
      ok "kept the backups in $INSTALL_DIR"
    fi
  fi
  rmdir "$INSTALL_DIR" 2>/dev/null || true
  say "Done. Your playlists in Music were left alone; delete them there if you like."
}

# ---------------------------------------------------------------------------
# checks
# ---------------------------------------------------------------------------

[ "$(uname -s)" = "Darwin" ] || die "SeTeR Shuffle drives the Music app, so it only runs on macOS."
for tool in osascript osacompile perl launchctl; do
  command -v "$tool" >/dev/null 2>&1 || die "Missing '$tool', which ships with macOS. Is this a normal macOS install?"
done

if [ "$UNINSTALL" = 1 ]; then
  do_uninstall
  exit 0
fi

[ -d "/System/Applications/Music.app" ] || [ -d "/Applications/Music.app" ] ||
  die "The Music app wasn't found. SeTeR Shuffle needs macOS 10.15 (Catalina) or newer."

say "SeTeR Shuffle setup"
say ""

# ---------------------------------------------------------------------------
# 1. install the scripts
# ---------------------------------------------------------------------------

say "1. Installing the scripts into $INSTALL_DIR"
PREV_PLAYLIST="$(current_playlist)"
mkdir -p "$INSTALL_DIR"
install_script "$MAIN"
install_script "$WRAP"
ok "installed $MAIN and $WRAP"

# ---------------------------------------------------------------------------
# 2. pick the playlist for the daily run
# ---------------------------------------------------------------------------

SCHEDULE=0
if [ "$NO_DAILY" = 1 ]; then
  say "2. Daily run: skipped (--no-daily)"
else
  say "2. Daily run"
  say "   Each morning SeTeR can shuffle one playlist in place (a backup is saved first)"
  say "   and refresh the SeTeR Rediscover playlist."
  PLAYLIST_LIST=""
  LIST_ERR="$(new_tmp)"
  if PLAYLIST_LIST="$(list_playlists 2>"$LIST_ERR")"; then
    count="$(printf '%s\n' "$PLAYLIST_LIST" | grep -c . || true)"
    ok "found $count playlist(s) in Music"
  else
    warn "Couldn't read your playlists from Music: $(tr '\n' ' ' <"$LIST_ERR")"
    warn "If macOS asked to let this app control Music, allow it (System Settings > Privacy & Security > Automation) and re-run setup."
    PLAYLIST_LIST=""
  fi

  if [ -z "$PLAYLIST" ] && [ "$ASSUME_YES" = 1 ] && [ -n "$PREV_PLAYLIST" ]; then
    PLAYLIST="$PREV_PLAYLIST"
  fi

  if [ -z "$PLAYLIST" ] && [ "$ASSUME_YES" != 1 ]; then
    if [ -n "$PLAYLIST_LIST" ]; then
      say "   Some of your playlists:"
      printf '%s\n' "$PLAYLIST_LIST" | head -n 15 | sed 's/^/     - /'
    fi
    tries=0
    while [ "$tries" -lt 3 ]; do
      ask "   Playlist to shuffle daily (blank to skip the daily run)" "$PREV_PLAYLIST"
      candidate="$REPLY"
      if [ -z "$candidate" ]; then break; fi
      if [ -z "$PLAYLIST_LIST" ] || printf '%s\n' "$PLAYLIST_LIST" | grep -Fxq -- "$candidate"; then
        PLAYLIST="$candidate"
        break
      fi
      warn "No regular playlist named \"$candidate\" (names must match exactly; smart playlists can't be shuffled)."
      tries=$((tries + 1))
    done
  elif [ -n "$PLAYLIST" ] && [ -n "$PLAYLIST_LIST" ]; then
    printf '%s\n' "$PLAYLIST_LIST" | grep -Fxq -- "$PLAYLIST" ||
      die "No regular playlist named \"$PLAYLIST\" in Music (names must match exactly)."
  fi

  if [ -n "$PLAYLIST" ]; then
    SCHEDULE=1
    if [ -z "$HOUR" ]; then
      ask "   Hour of the day to run it (0-23)" "8"
      HOUR="$REPLY"
      case "$HOUR" in
        '' | *[!0-9]*) die "The hour must be a number from 0 to 23." ;;
      esac
      [ "$HOUR" -ge 0 ] && [ "$HOUR" -le 23 ] || die "The hour must be a number from 0 to 23."
    fi
  else
    say "   No playlist chosen, so no daily schedule. You can re-run setup any time."
  fi
fi

if [ "$SCHEDULE" = 1 ]; then
  set_string_property "$INSTALL_DIR/$MAIN" defaultDailyPlaylist "$PLAYLIST"
  set_string_property "$INSTALL_DIR/$WRAP" playlistName "$PLAYLIST"
  ok "daily playlist set to \"$PLAYLIST\""
fi

# ---------------------------------------------------------------------------
# 3. check the scripts compile
# ---------------------------------------------------------------------------

say "3. Checking the scripts"
for f in "$MAIN" "$WRAP"; do
  osacompile -o "$WORK/check.scpt" "$INSTALL_DIR/$f" 2>"$WORK/check.err" ||
    die "$f didn't compile: $(cat "$WORK/check.err"). Please open an issue and include this message."
  rm -f "$WORK/check.scpt" "$WORK/check.err"
done
ok "both scripts compile"

# ---------------------------------------------------------------------------
# 4. apps
# ---------------------------------------------------------------------------

if [ "$NO_APPS" = 1 ]; then
  say "4. Apps: skipped (--no-apps)"
else
  say "4. Building the apps in $APP_DIR"
  build_app "$INSTALL_DIR/$MAIN" "$MAIN_APP"
  ok "$MAIN_APP (menu: Shuffle, Rediscover, Remove duplicates, Undo)"
  if [ "$SCHEDULE" = 1 ]; then
    build_app "$INSTALL_DIR/$WRAP" "$WRAP_APP"
    ok "$WRAP_APP (one click: shuffle \"$PLAYLIST\" + refresh Rediscover)"
  else
    say "   (skipping the one-click daily app: it needs a playlist)"
  fi
fi

# ---------------------------------------------------------------------------
# 5. schedule
# ---------------------------------------------------------------------------

if [ "$SCHEDULE" = 1 ]; then
  say "5. Scheduling the daily run at ${HOUR}:00"
  write_plist "$PLAYLIST" "$HOUR"
  if launchd_load; then
    ok "scheduled (if your Mac is asleep then, it runs when it wakes)"
  else
    warn "Couldn't load the schedule. Try: launchctl load \"$PLIST_PATH\""
  fi
else
  say "5. Schedule: none"
fi

# ---------------------------------------------------------------------------
# 6. preview
# ---------------------------------------------------------------------------

if [ "$NO_PREVIEW" != 1 ] && { [ "$ASSUME_YES" = 1 ] || confirm "6. Run a read-only Rediscover preview now to test everything? (can take a minute on a big library)" y; }; then
  say ""
  say "Previewing (nothing in Music will be changed)..."
  if ! /usr/bin/osascript "$INSTALL_DIR/$MAIN" rediscover-preview; then
    warn "The preview failed. If macOS asked for permission to control Music, allow it in"
    warn "System Settings > Privacy & Security > Automation, then re-run setup."
  fi
fi

say ""
say "All set."
if [ "$NO_APPS" != 1 ]; then
  say "  Menu app:        open \"$APP_DIR/$MAIN_APP\""
  if [ "$SCHEDULE" = 1 ]; then
    say "  One-click app:   open \"$APP_DIR/$WRAP_APP\""
  fi
fi
say "  From Terminal:   /usr/bin/osascript \"$INSTALL_DIR/$MAIN\" rediscover-preview"
say "  Log:             $LOG_FILE"
say "  Undo a shuffle:  open the menu app and choose \"Undo last shuffle\""
say "  Remove it all:   bash setup.sh --uninstall"
say "Tip: the first time the apps (or the daily job) run, macOS may ask again for permission to control Music; allow it."
