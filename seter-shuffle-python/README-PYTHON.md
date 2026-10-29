# SeTeR Shuffle, Python experimental core

Experimental only. Stable v2.6 (AppleScript) is untouched, and the daily
launchd run still uses it. This Python version is opt-in: nothing here
installs itself, schedules itself, or replaces the stable install.

## Architecture: what each part does

```
Music app
  │  dump-library.applescript  (read-only: library/playlist -> JSON)
  ▼
Python core (seter_shuffle/)   (decides an ordering, nothing else)
  │  --order-txt: one persistent ID per line
  ▼
apply-order.applescript        (snapshot -> build -> verify -> restore)
```

- **Python core** (`seter_shuffle/`, standard library only, no pip
  dependencies): Fisher-Yates shuffle with v2.6 artist spacing,
  Rediscover scoring/picking from v2.6, and Flow ordering from the
  experimental AppleScript build. It works only on a JSON dump. It
  never opens Music, never edits the dump, and never writes a playlist.
  This is the part that is fully testable on any machine.
- **Bridge** (`bridge/`, three small AppleScript files): the only code
  that talks to Music. `dump-library.applescript` dumps a library or
  playlist to JSON. `apply-order.applescript` snapshots a playlist's
  IDs to a backup file BEFORE changing anything, rebuilds it in the
  given order, verifies count plus every expected ID, and restores
  from the backup on any failure; it refuses smart playlists and
  anything that is not a regular user playlist, and fails if the
  library shrank during the run. `undo.applescript` replays a backup
  file. The bridge never decides an order.
- **Runner** (`run.sh`): wires bridge -> core -> bridge, logs to
  `~/Library/Logs/seter-shuffle-python/run.log`, and keeps backups
  under the same directory. `check-python.sh` verifies a real python3
  before Music is touched (see below).

The interchange between core and bridge is deliberately split in two:
JSON for humans and the Python core, and a plain one-ID-per-line text
file for the bridge, because AppleScript has no JSON parser and
parsing JSON by hand in AppleScript would be a new bug factory.

## Commands on a Mac

From this directory:

```bash
./run.sh flowPreview            # print the would-be Flow order, change nothing
./run.sh flow                   # build or refresh "SeTeR Flow"
./run.sh shuffle                # shuffle the whole library into "SeTeR Shuffle"
./run.sh shuffle "My Playlist"  # shuffle one playlist in place
./run.sh rediscover-preview     # print Rediscover picks, change nothing
./run.sh rediscover             # refresh "SeTeR Rediscover" (history is
                                # recorded only after a successful apply)
./run.sh undo "SeTeR Flow"      # restore a playlist from its last backup
```

Direct core commands (no Music involved, useful for testing):

```bash
python3 -m seter_shuffle.cli flowPreview --library dump.json --seed 42
python3 -m seter_shuffle.cli flow --library dump.json --out order.json --order-txt order.txt
python3 -m seter_shuffle.cli shuffle --library dump.json --out order.json --order-txt order.txt
python3 -m seter_shuffle.cli rediscover-preview --library dump.json --history rediscover-history.tsv
python3 -m seter_shuffle.cli record-history --history rediscover-history.tsv --ids-file order.txt
```

`flowPreview` and `rediscover-preview` never call the apply script and
never write history. `rediscover` (the core command) also does not
write history; the runner records it only after the apply succeeds, so
a failed apply never burns a song's cooldown.

## The python3 check

macOS ships a python3 stub that just prompts to install developer
tools. `check-python.sh` requires a real interpreter (3.9+) and fails
loudly otherwise, instead of letting a scheduled run break silently:

```bash
./check-python.sh
# -> /usr/bin/python3 (Python 3.12.3)   on success
```

If it fails, install real Python (Xcode Command Line Tools with
`xcode-select --install`, python.org, or Homebrew) or point
`SETER_PYTHON` at a real interpreter, for example:

```bash
SETER_PYTHON=/opt/homebrew/bin/python3 ./run.sh flowPreview
```

## Settings

Defaults match v2.6 plus the experimental Flow settings. Override them
on the core command line, for example `--flow-size 30`,
`--artist-spacing 1`, `--rediscover-min 30`, `--max-per-artist 2`,
`--cooldown-days 14`, `--stale-days 60`. The runner uses defaults;
edit `run.sh` if you want different ones baked in.

## What was actually tested, and what was not

Tested here, for real (31 tests, all passing):

```bash
python3 -m unittest discover -s tests -v
```

Shuffle set preservation and replayable seeds, artist spacing
(including the featuring rule and the best-effort limit), Flow energy
(missing BPM/genre defaults, bands, nudges, clamps), the wave arc,
Flow with 0/1/2 songs, Flow eligibility (disliked/unchecked out,
skip-heavy kept, unlike Rediscover), Flow artist spacing winning over
vibe, Rediscover eligibility/weights/target clamps, max-per-artist and
cooldown enforcement, history load/record roundtrips, duplicate-ID
rejection, and CLI previews proving they leave the input file
byte-identical and write nothing to any library.

NOT tested, and not claimed to work until a Mac run proves it (the
full list is in CHANGELOG-EXPERIMENTAL-PYTHON.md):

- All three bridge scripts: every Music interaction, including bulk
  property reads for bpm/year/dates, `month as integer` and the
  date-component ISO formatting in the dump script, `first track ...
  whose persistent ID is ...`, duplicate-to-playlist ordering, and the
  verify/restore paths.
- `run.sh` end to end: it needs osascript and Music, neither of which
  exists on the Linux machine this was built on. Its shell syntax was
  checked (`bash -n`), and its python-path parsing was fixed during
  review, but no Mac run has happened.
- The macOS python3 stub behaviour: the check script is written to
  fail loudly, but the stub's exact behaviour on a given Mac has not
  been observed from here.

Suggested Mac verification order: `./check-python.sh` first, then
`./run.sh flowPreview` (changes nothing), then `./run.sh flow` on a
small test playlist if possible, then check the playlist order, the
run log, and `./run.sh undo "SeTeR Flow"` restoring the backup.

## Known differences and quirks, kept on purpose

- Flow's 2-song arc ends at the peak instead of easing down, exactly
  as in the AppleScript experimental build. Fixing it would make the
  two builds disagree; it is flagged, not silently changed.
- Genre grouping is substring matching, so "K-Pop" lands in the pop
  group, exactly as in the AppleScript build.
- Rediscover picks are shuffled and artist-spread after picking, as
  in v2.6; the playlist does not play best-songs-first.
- Artist spacing is best effort. With spacing=2, at least 2 songs must
  sit between repeats, so a library dominated by one or two artists
  cannot be fully separated, and the pass gives up rather than looping.
