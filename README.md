# SeTeR Shuffle

True-random (Fisher-Yates) shuffle for Apple Music, with library protection.
macOS AppleScript — no developer account, no API tokens, no dependencies.

## What it does

- **Shuffle** — Shuffle your whole library into the `SeTeR Shuffle` playlist,
  or shuffle any playlist *in place* (name, artwork and description are kept).
  Optional no-same-artist-back-to-back.
- **Rediscover** — Forgotten favorites into `SeTeR Rediscover`: songs with 2+
  plays unplayed for 60+ days, topped up with long-unplayed 1-play songs and
  never-played old adds. Scales with your library (1% of songs, 30–500).
  Refreshed in place so its cover artwork survives.
- **Remove duplicates** — Clean repeated songs out of any playlist, keeping
  the original order.
- **Undo last shuffle** — Puts a playlist back exactly how it was before the
  last in-place change, from the automatic pre-change backup.
- **Daily automatic run** — `osascript SeTeR-shuffle.applescript daily "Playlist"`
  shuffles the named playlist in place and refreshes `SeTeR Rediscover` with
  no dialogs. Meant to be scheduled with the included launchd plist (8:00 AM).

## Safety

- Refuses to touch anything that isn't a regular user playlist (deleting
  "tracks" from the Library itself would remove songs from your library).
- Library size is checked before and after every playlist rewrite — if it
  shrinks, the run stops with a loud error.
- Every in-place change snapshots the playlist (song count + persistent IDs)
  to `~/Library/Logs/seter-shuffle-backup.txt` **before** making changes,
  then verifies afterwards. On any failure the playlist is restored from the
  backup and the run aborts.
- Once a day, the daily run saves a manifest of your whole library
  (ID, artist, album, title) to `~/Documents/SeTeRShuffle/backups/`, kept for
  14 days.

## Files

| File | What it is |
|---|---|
| `SeTeR-shuffle.applescript` | The main script (interactive menu + daily mode) |
| `SeTeR-sandwich-shuffle.applescript` | One-click wrapper: runs the daily refresh, no questions asked |
| `com.seter.daily.plist` | launchd job: daily 8:00 AM run |

## Requirements

- macOS with the Music app
- That's it. Open a `.applescript` file with Script Editor (built in).

## Install

1. Grab the latest release zip from the
   [Releases page](https://github.com/0Recneps0/seter-shuffle/releases)
   (or clone this repo).
2. Save `SeTeR-shuffle.applescript` as
   `~/Documents/SeTeRShuffle/SeTeR-shuffle.applescript`.
3. **Manual app (optional):** open it in Script Editor, then
   File → Export → File Format: **Application**, e.g. into Applications.
   Double-clicking gives you the Shuffle / Rediscover / Remove duplicates /
   Undo menu.
4. **Daily run (optional):** copy `com.seter.daily.plist` to
   `~/Library/LaunchAgents/`, then run once in Terminal:
   ```bash
   launchctl load ~/Library/LaunchAgents/com.seter.daily.plist
   ```
   The plist calls the script with playlist `my new sandwich recipe` —
   edit the plist's `ProgramArguments` (and the script's
   `defaultDailyPlaylist` property) to use your own playlist.
   The plist assumes username `recneps`; adjust the paths if yours differs.
5. On first run, allow the script to control the Music app when macOS asks
   (System Settings → Privacy & Security → Automation).

## Usage

- **App:** double-click → pick Shuffle, Rediscover, Remove duplicates,
  or Undo last shuffle.
- **Sandwich wrapper:** export `SeTeR-sandwich-shuffle.applescript` as an
  Application too for a one-click daily refresh. (It expects the main script
  at `~/Documents/SeTeRShuffle/SeTeR-shuffle.applescript`.)
- **Terminal:**
  ```bash
  /usr/bin/osascript ~/Documents/SeTeRShuffle/SeTeR-shuffle.applescript daily "my new sandwich recipe"
  ```

## Logs & backups

- `~/Library/Logs/seter-shuffle.log` — progress and errors, rotates at 1 MB
- `~/Library/Logs/seter-shuffle-backup.txt` — snapshot before each in-place
  change (used by Undo)
- `~/Documents/SeTeRShuffle/backups/` — daily whole-library manifests,
  kept 14 days

## Settings

At the top of `SeTeR-shuffle.applescript`:

- `rediscoverPercent` / `rediscoverMin` / `rediscoverMax` — Rediscover size
  (default: 1% of library, 30–500 songs)
- `staleDays` — what counts as "forgotten" (default: 60)
- `backupKeepDays` — manifest retention (default: 14)
- `defaultDailyPlaylist` — playlist the daily run shuffles

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.seter.daily.plist
rm ~/Library/LaunchAgents/com.seter.daily.plist
rm -rf ~/Documents/SeTeRShuffle
```

## Version

v2.3 — see [Releases](https://github.com/0Recneps0/seter-shuffle/releases)
for packaged downloads.
