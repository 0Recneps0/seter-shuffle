# SeTeR Shuffle

True-random (Fisher-Yates) shuffle for Apple Music, with library protection.
macOS AppleScript: no developer account, no API tokens, no dependencies.

Music's built-in shuffle only changes playback order. SeTeR Shuffle actually **rewrites a playlist's order**, so the shuffle is genuinely random and stays that way on every device the playlist syncs to. It also builds a **Rediscover** playlist of songs you used to love and forgot about, and it can run by itself every morning.

Everything is built around one rule: **never lose songs.** Every change is backed up first, verified afterwards, and rolled back automatically if anything looks wrong.

## What it does

- **Shuffle**: shuffle your whole library into the `SeTeR Shuffle` playlist
  (choose 100 / 250 / 500 / 1000 / all songs), or shuffle any playlist *in place*
  (name, artwork and description are kept). Optional no-same-artist-back-to-back.
- **Rediscover**: forgotten favorites into `SeTeR Rediscover`: songs with 2+
  plays unplayed for 60+ days, topped up with long-unplayed 1-play songs and
  never-played old adds. Scales with your library (1% of songs, 30 to 500).
  Refreshed in place so its cover artwork survives.
- **Remove duplicates**: clean repeated songs out of any playlist, keeping
  the original order.
- **Undo last shuffle**: puts a playlist back exactly how it was before the
  last in-place change, from the automatic pre-change backup.
- **Daily automatic run**: `osascript SeTeR-shuffle.applescript daily "Playlist"`
  shuffles the named playlist in place (removing duplicates unless you turn that off,
  no same artist back to back) and refreshes `SeTeR Rediscover` with no dialogs. Meant to be
  scheduled with the included launchd plist (8:00 AM).

## Safety

- Refuses to touch anything that isn't a regular user playlist (deleting
  "tracks" from the Library itself would remove songs from your library).
- Library size is checked before and after every playlist rewrite. If it
  shrinks, the run stops with a loud error.
- Every in-place change snapshots the playlist (song count + persistent IDs)
  to `~/Library/Logs/seter-shuffle-backup.txt` **before** making changes,
  then verifies afterwards. On any failure the playlist is restored from the
  backup and the run aborts. If the backup can't be written, nothing is changed.
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
   The plist calls the script with playlist `my new sandwich recipe`.
   Edit the plist's `ProgramArguments` (and the script's
   `defaultDailyPlaylist` property) to use your own playlist.
   The plist has `/Users/recneps/` baked into three paths (the script and the
   two log files), so change `recneps` to your own username before loading it.
   If your Mac is asleep at 8:00 AM, launchd runs the job when it wakes.
5. On first run, allow the script to control the Music app when macOS asks
   (System Settings → Privacy & Security → Automation).

## Usage

- **App:** double-click → pick Shuffle, Rediscover, Remove duplicates,
  or Undo last shuffle. Remove duplicates and Undo ask for confirmation first.
- **Sandwich wrapper:** export `SeTeR-sandwich-shuffle.applescript` as an
  Application too for a one-click daily refresh. It shows a notification while
  it works, a short summary when it finishes, and an **Open Log** button if
  something goes wrong. (It expects the main script at
  `~/Documents/SeTeRShuffle/SeTeR-shuffle.applescript`.)
- **Terminal:**
  ```bash
  /usr/bin/osascript ~/Documents/SeTeRShuffle/SeTeR-shuffle.applescript daily "my new sandwich recipe"
  ```

The daily run does the following, in order: saves the library manifest (once per
day), removes duplicates from the named playlist (unless `dailyRemoveDuplicates` is `false`) and shuffles it in place,
refreshes `SeTeR Rediscover`, stamps a `Last reshuffled:` / `Last refreshed:`
line into each playlist's description (existing description text is kept), and
logs everything. If anything fails it **exits with an error code**, so
schedulers and the wrapper app can tell.

## Rediscover

`SeTeR Rediscover` is filled with random songs from three tiers, best first:

1. **Forgotten favorites**: played 2+ times, not played in the last 60 days
2. **Gathering dust**: played once, not played in the last 60 days
3. **Never got around to it**: never played, added more than 60 days ago

The target size scales with your library: 1% of your songs, never fewer than 30
and never more than 500.

| Songs in library | Rediscover playlist |
|---|---|
| 2,000 | 30 (minimum) |
| 10,000 | 100 |
| 23,000 | 230 |
| 50,000+ | 500 (maximum) |

## Logs & backups

- `~/Library/Logs/seter-shuffle.log`: progress, errors, and every duplicate the daily
  run removed (`removing duplicate: Artist - Title`). Rotates at 1 MB.
  The launchd plist also points its stdout/stderr at this same file, so if the
  daily run fails you'll see the raw `osascript` error there as well.
- `~/Library/Logs/seter-shuffle-backup.txt`: snapshot before each in-place
  change (used by Undo). It is overwritten by each run, so Undo always means
  "undo the most recent in-place change", and an undo itself can't be undone.
- `~/Documents/SeTeRShuffle/backups/`: daily whole-library manifests
  (`library-manifest-YYYY-MM-DD.tsv`), kept 14 days

## Settings

At the top of `SeTeR-shuffle.applescript`:

| Property | Default | Meaning |
|---|---|---|
| `rediscoverPercent` | `1` | Rediscover holds this % of your library... |
| `rediscoverMin` | `30` | ...but never fewer than this many songs |
| `rediscoverMax` | `500` | ...and never more than this many |
| `staleDays` | `60` | What counts as "forgotten" |
| `backupKeepDays` | `14` | Manifest retention |
| `defaultDailyPlaylist` | `my new sandwich recipe` | Playlist the daily run shuffles when none is given |
| `dailyRemoveDuplicates` | `true` | `true`: the daily run removes repeated songs from the playlist. `false`: keeps every entry, so the song count never changes |

## Changing playlist names

There are three playlists involved, and each is changed in a different place.

| Playlist | What it is | Where the name lives |
|---|---|---|
| Your daily playlist | The playlist the daily run shuffles in place | `com.seter.daily.plist`, `defaultDailyPlaylist` in `SeTeR-shuffle.applescript`, and `playlistName` in `SeTeR-sandwich-shuffle.applescript` |
| `SeTeR Shuffle` | Where the "entire library" shuffle goes | `SeTeR-shuffle.applescript` |
| `SeTeR Rediscover` | The Rediscover playlist | `SeTeR-shuffle.applescript` |

**Tip:** rename the playlist in the Music app *first*, then change the name in the script. If you only change the script, it will create a brand-new playlist with the new name and leave the old one (and its cover artwork) behind.

### Your daily playlist

Names must match the playlist in Music **exactly** (spelling, capitals, spaces). Change it in these places:

1. `com.seter.daily.plist`: the last `<string>` under `ProgramArguments` (currently `my new sandwich recipe`). Then reload the job:
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.seter.daily.plist
   launchctl load ~/Library/LaunchAgents/com.seter.daily.plist
   ```
2. `SeTeR-shuffle.applescript`: the `defaultDailyPlaylist` property near the top (used when no name is passed).
3. `SeTeR-sandwich-shuffle.applescript`: the `playlistName` property near the top.
4. If you run it from Terminal, the name at the end of the command.

If you re-exported either script as an app, export it again after editing.

### `SeTeR Shuffle` (library shuffle playlist)

Open `SeTeR-shuffle.applescript` in Script Editor and find this line in the `doShuffle` handler:

```applescript
set destName to "SeTeR Shuffle"
```

Change the text in quotes to your new name. Leave the other "SeTeR Shuffle" strings alone: those are the titles of notifications and dialogs, not the playlist name.

### `SeTeR Rediscover`

In Script Editor, use **Edit → Find → Find...** (⌥⌘F), search for `SeTeR Rediscover`, and **Replace All** with your new name. That text only appears as the playlist name (in the playlist lookup, the playlist creation, and the notification messages), so replacing every occurrence is safe.

Then re-export the script as an app if you use the app version.

## How it works

- **Shuffle:** the script reads the playlist's tracks, shuffles their order with
  Fisher-Yates, then writes them back. For an in-place shuffle the new order is
  staged in a temporary playlist (`SeTeRShuffleTemp`), the old songs are removed
  from the playlist, and the staged songs are moved in. Staging is needed
  because track references into a playlist go stale once its songs are deleted.
- **No same artist twice:** when a track repeats the previous track's artist, it
  is swapped with the nearest later track by a different artist, so the order
  stays close to a true shuffle. Songs with no artist tag are never treated as a
  repeat. If only one artist's songs remain at the very end, they stay together.
- **Duplicates:** detected by Music's persistent ID, meaning the same library
  track listed more than once in a playlist. Different versions or copies of a
  song are different tracks and are *not* treated as duplicates.

## Limitations

- Large library shuffles are slow, because Music's AppleScript interface adds
  songs one at a time. Use the 100 / 250 / 500 / 1000 size options for quicker runs.
- Only songs are handled (not videos or podcasts).
- Smart playlists can't be shuffled, since Music controls their order.
- Undo restores only the single most recent backup.

## Troubleshooting

- **"Not authorized to send Apple events to Music":** allow it in
  System Settings → Privacy & Security → Automation.
- **"Playlist ... not found":** the playlist name passed to `daily` must match exactly.
- **Something looks wrong after a run:** check `~/Library/Logs/seter-shuffle.log`
  and use **Undo last shuffle** from the app.

## Why did my playlist's song count drop?

By default the daily run **removes duplicates**: if the same song is in the playlist more than once, only the first copy is kept. So a playlist can legitimately go from, say, 646 to 635 songs. Every removed song is listed in the log, and the notification says how many were removed:

```bash
grep -E "snapshot|removing duplicate|shuffled" ~/Library/Logs/seter-shuffle.log | tail -30
```

You can also count the repeats in the latest backup (the first four lines are a header):

```bash
tail -n +5 ~/Library/Logs/seter-shuffle-backup.txt | sort | uniq -c | awk '$1>1 {n+=$1-1} END {print n+0}'
```

If you'd rather keep every entry, set `dailyRemoveDuplicates` to `false` at the top of `SeTeR-shuffle.applescript`. If the log shows no removed duplicates but the count still dropped, check it for `VERIFY FAILED`, `RESTORING` or `LIBRARY SHRANK` lines. Those mean the safety checks caught a problem, and **Undo last shuffle** will put the playlist back.

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.seter.daily.plist
rm ~/Library/LaunchAgents/com.seter.daily.plist
rm -rf ~/Documents/SeTeRShuffle
```

## Disclaimer

Provided as-is. The scripts are designed to be safe, but they automate changes
to your music library, so keep a backup (Time Machine, or the manifests above)
and try them on a small test playlist first.

## Version

v2.4. See [Releases](https://github.com/0Recneps0/seter-shuffle/releases)
for packaged downloads.
