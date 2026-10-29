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
- **Bridge** (`bridge/`, AppleScript files): the only code
  that talks to Music. `dump-library.applescript` dumps a library or
  playlist to JSON. `sort-probe.applescript` measures the
  end-to-end build-to-list mapping on a throwaway the user sets to
  the target playlist's sort (Playlist Order descending for the
  2026-10-28 failure), reporting forward, reversed, or other
  (which aborts everything); run.sh records that mapping and
  requires a fresh one (24 hours) before every apply and undo.
  The old `probe-order.applescript` (fresh 3-song probe) is a
  standalone sanity check only and is consulted by no build: a
  fresh playlist does not share a real playlist's sort, and the
  track `index` channel it used is not a manual-order reference
  (2026-10-29 diagnostic; see BRIDGE-SAFETY.md mode 30).
  `apply-order.applescript` snapshots a playlist's IDs to a backup
  file BEFORE changing anything, rebuilds it under the recorded
  mapping, verifies exactly against the desired list-read order,
  and restores from the backup on any failure; it refuses the
  Library itself, smart playlists, and anything that is not a
  regular user playlist, refuses ambiguous playlist names instead
  of guessing, and fails if the library shrank during the run.
  Every rebuild first proves its delete took effect: it deletes,
  re-reads, and confirms 0 song entries, retrying up to 5 times
  with a 5-second settle delay, and duplicates nothing if entries
  remain (2026-10-29 doubling failure: a real playlist doubled to
  1612 entries, consistent with a lagging delete; the guard does
  not depend on that mechanism being proven). `undo.applescript`
  replays a backup file with the same strictness, and snapshots
  the current playlist first so a failed undo is recoverable.
  `restore-original.applescript` is a one-off recovery script that
  also takes a recorded mapping (no probe, no flip), runnable
  through `./run.sh restore` with the same freshness-checked
  mapping gate as undo. Backups are per-run: the apply writes to
  a fresh per-run snapshot file, installed as the main backup only
  after a verified successful apply, so a failed run can never
  overwrite the only good backup (the 00:41 run did exactly that
  under the old scheme). The bridge never decides an order, and
  never flips on failure: a failed verify restores and exits
  non-zero. Full failure-mode table, the one case AppleScript
  cannot cover (power loss / force-quit mid-write), and the Mac
  verification procedure: see `BRIDGE-SAFETY.md`. The bridge has
  been reviewed line by line but never executed: this machine has
  no Music app or osascript, so until the Mac procedure in
  `BRIDGE-SAFETY.md` has been run, treat it as reviewed, not
  tested.
- **Validation** (`seter_shuffle/validate.py`, plus `validate-order`
  and `validate-backup` CLI commands): the same refuse rules as the
  bridge, applied in Python before osascript ever runs, so a bad
  order is caught while the playlist is still untouched. Empty
  orders, IDs missing from the dump, shuffle orders that are not
  exactly the dump's songs (same songs, same multiplicities),
  orders repeating an ID more times than the dump does, truncated
  orders (the text file must agree exactly with the order JSON),
  and malformed files are all refused. Backups are validated too,
  with one deliberate difference: duplicates are allowed in a
  backup (a real playlist can hold the same song twice) and an empty
  backup is valid (it snapshots an empty playlist).
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
./run.sh audit                  # tag-coverage audit, change nothing (run this first)
./run.sh flowPreview            # print the would-be Flow order, change nothing
./run.sh flow                   # build or refresh "SeTeR Flow"
./run.sh shuffle                # shuffle the whole library into "SeTeR Shuffle"
./run.sh shuffle "My Playlist"  # shuffle one playlist in place
./run.sh rediscover-preview     # print Rediscover picks, change nothing
./run.sh rediscover             # refresh "SeTeR Rediscover" (history is
                                # recorded only after a successful apply)
./run.sh undo "SeTeR Flow"      # restore a playlist from its last backup
./run.sh dedupe "My Playlist"   # remove duplicate entries (unique songs,
                                # first-occurrence order); applies nothing
                                # if the playlist has no duplicates.
                                # NOTE: dedupe preserves the current
                                # list-read order, not a backup order,
                                # so on a reversed doubled playlist
                                # it yields unique songs in reversed
                                # order; a backup-order restore is a
                                # separate step afterwards.
./run.sh restore "My Playlist" backup.txt
                                # restore a playlist from a given backup
                                # file (freshness-checked mapping, same
                                # gate as undo)
```

Direct core commands (no Music involved, useful for testing):

```bash
python3 -m seter_shuffle.cli audit --library dump.json
python3 -m seter_shuffle.cli flowPreview --library dump.json --seed 42
python3 -m seter_shuffle.cli flow --library dump.json --out order.json --order-txt order.txt
python3 -m seter_shuffle.cli shuffle --library dump.json --out order.json --order-txt order.txt
python3 -m seter_shuffle.cli dedupe --library dump.json --out order.json --order-txt order.txt
python3 -m seter_shuffle.cli rediscover-preview --library dump.json --history rediscover-history.tsv
python3 -m seter_shuffle.cli record-history --history rediscover-history.tsv --ids-file order.txt
python3 -m seter_shuffle.cli validate-order --library dump.json --order-txt order.txt --order-json order.json --mode shuffle
python3 -m seter_shuffle.cli validate-order --library dump.json --order-txt order.txt --order-json order.json --mode dedupe
python3 -m seter_shuffle.cli validate-backup --backup backup.txt
```

`flowPreview` and `rediscover-preview` never call the apply script and
never write history. `rediscover` (the core command) also does not
write history; the runner records it only after the apply succeeds, so
a failed apply never burns a song's cooldown. `audit` never touches
Music at all: it only counts what is in a dump file.

## BPM is not attached to every song, and Flow now handles that

No, not every song in Apple Music has a BPM. Music does not analyse
tempo for you: the BPM field comes from the track's own metadata, and
it is often blank, especially for rips, older files, and tracks whose
source never wrote a tempo tag. A library with most BPM missing is
normal metadata, not proof the dump failed.

That is exactly what Spencer's 2026-10-28 preview showed: 940 songs
dumped, 938 eligible, but almost every energy at exactly 50, because
missing BPM defaulted to 50 and his gospel/Christian genres matched
no genre group. Two causes look identical in a preview, and `audit`
separates them: if BPM is present for *some* songs, the dump works
(a dump bug would lose BPM for the whole list at once) and the rest
truly lack BPM metadata. If BPM is present for *zero* songs, suspect
the dump script first.

The missing-BPM fallback model (songs WITH BPM score exactly as
before) is: base 50, an expanded genre map (gospel/christian/worship
-2, latin/reggaeton +6, afrobeats/reggae +4, soundtrack -3, old
groups unchanged), tiered plays (1-4 plays +2, 5-19 +4, 20-49 +6,
50+ +9), rating (3 stars +2, 4-5 stars +5, 1-2 stars -10), favorited
+5, and a -5 penalty only when at least 3 plays+skips exist and more
than half were skips (skip-heavy songs stay eligible; they just do
not score like never-skipped ones). The fallback spread is
deliberately narrower than the BPM range: without a tempo, plays and
genre are weak signals, and a wide spread would be guessing a tempo,
not measuring one. On a varied missing-BPM fixture the old model gave
6 distinct energies with three songs stuck at 50; the fallback gives
9 distinct energies over 38-69, with only the truly blank song
(unknown genre, no plays, no rating, not favorited) still at 50.

Tie-breaking also changed: on an exact cost tie the walk now prefers
a genre group different from the previous pick, then higher
familiarity (plays, favorited, rating), then the earliest pool song,
so flat-energy pools stop coming out in raw library order. The order
stays deterministic.

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

Tested here, for real (128 tests, all passing):

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
rejection, CLI previews proving they leave the input file
byte-identical and write nothing to any library, plus the new work:
audit counts matching a known fixture (including BPM zero vs
missing), the missing-BPM spread, gospel/Christian/latin/afrobeats/
soundtrack genre mapping, BPM-present songs scoring exactly as
before, the skip penalty applying only without BPM, and the
movement/familiarity tie-break being deterministic, plus the new
work: dedupe first-occurrence order (including the reversed-doubled
shape), dedupe validation refusing repeats, drops, and invented
IDs, the CLI dedupe command on dump files, and structural guards
for the delete-empty handler in all four bridge scripts, the
logfile-only mapping reader, the per-run backup chain, the
sort-probe mapping deletion on failure, and the restore command.

NOT tested, and not claimed to work until a Mac run proves it (the
full list is in CHANGELOG-EXPERIMENTAL-PYTHON.md). This warning is
stronger than it was for .4, because .4 was also "reviewed, not
tested" and then failed on a real 806-song playlist (its pre-undo
snapshot came back the exact reverse of the original backup; see
BRIDGE-SAFETY.md mode 29):

- All bridge scripts: every Music interaction, including bulk
  property reads for bpm/year/dates, `month as integer` and the
  date-component ISO formatting in the dump script, `first track ...
  whose persistent ID is ...`, duplicate-to-playlist ordering, the
  verify/restore paths, and now the probe itself (including whether
  the track `index` property is exposed on playlist tracks at all).
- `run.sh` end to end: it needs osascript and Music, neither of which
  exists on the Linux machine this was built on. Its shell syntax was
  checked (`bash -n`), and its python-path parsing was fixed during
  review, but no Mac run has happened.
- The macOS python3 stub behaviour: the check script is written to
  fail loudly, but the stub's exact behaviour on a given Mac has not
  been observed from here.

Suggested Mac verification order: `./check-python.sh` first, then
the BRIDGE-SAFETY.md Stage 0 sequence: the read-only diagnostic on
the target, the UI sort check in Music, then
`./run.sh sortprobe "<throwaway>"` on a throwaway set to the
target's sort (Playlist Order descending for the 2026-10-28
failure), which must return a forward or reversed mapping and
restore the throwaway; an "other" mapping aborts everything by
design. The old `./run.sh probe` (fresh 3-song probe) is a
standalone sanity check only and does not substitute for the
sort-matched probe. Then `./run.sh audit` (changes nothing, and
answers whether BPM is truly missing or the dump is failing), then
`./run.sh flowPreview` (changes nothing), then the full throwaway
procedure in BRIDGE-SAFETY.md (Stage 0 controls, Stage 1 happy
path, Stage 2 negative tests, Stage 3 a real playlist you can
afford to have rewritten, with explicit approval). Nothing in
this procedure runs on a real playlist first, and nothing runs on
"My New Sandwich Recipe" until Stage 3 at the earliest.

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
