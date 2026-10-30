# SeTeR Shuffle, Python core (v3.0.4)

This tree is the v3.0.4 stable tree on the main branch. The v2.6
AppleScript build on main is not edited by this tree; it is only
disabled, by an explicit migration step, when the user runs the
one-click installer below.

## One-click install or update (v3.0.4)

Download the stable zip, unzip it, double-click
`SeTeR-Shuffle-Install.command` (or run `bash install-or-update.sh`),
and answer yes once. That one confirmation installs or updates
`~/Documents/SeTeRShufflePython` to v3.0.4, writes and loads the
8:00 AM `com.seter.python.daily` plist, and switches the daily
job from v2.6 to Python (migration), unless v2.6 is already
disabled. Backups, logs, and Rediscover history are kept; the
v2.6 script and backups are never deleted or edited; rollback
is `bash ~/Documents/SeTeRShufflePython/migrate-to-python.sh --rollback`.

NEW IN v3.0.2: the 8am daily run AUTO SELF-PROBES. Before it
builds anything, it runs `./run.sh selfprobe` on the daily
playlist and on "SeTeR Rediscover", measuring each mapping on
the target itself under its own sort (Music remembers each
playlist's own sort, so no throwaway sort needs matching and
no mapping can transfer between targets). The 48-hour manual
probe chore is gone; the mapping gate stays: a failed
self-probe fails the whole daily run closed before any build,
and an "other" mapping still aborts. A self-probe on a
playlist with duplicate entries refuses and changes nothing,
so a doubled playlist cannot be auto-probed; since v3.0.4
it is cleaned by trial-dedupe instead (see NEW IN v3.0.4
below), which verifies its own mapping without probing.
You can also self-probe by hand any time:
`./run.sh selfprobe "My New Sandwich Recipe"`.

NEW IN v3.0.3: menu and direct builds AUTO SELF-PROBE too.
v3.0.2 only auto-probed the daily run, so the menu still
refused on a missing mapping. Now every build path (menu,
direct shuffle, rediscover, dedupe, flow, undo, restore)
self-probes the target itself first when no fresh mapping
is recorded, and reuses a fresh mapping with no re-probe.
A failed probe aborts before any dump or apply, with the
probe error named. A doubled playlist still fails closed
at the probe (duplicate refusal unchanged) until deduped.

NEW IN v3.0.4: trial-dedupe breaks that deadlock. Dedupe
no longer probes first: a clean playlist applies nothing
and needs no mapping, a fresh mapping is used directly,
and otherwise dedupe tries its known deduped order
(first occurrence of each song) under mapping forward,
verifies the list read against it, and on failure
restores from the per-run snapshot and tries reversed.
The first mapping that verifies wins and is recorded, so
the next build reuses it; if neither verifies, the
playlist is restored to its pre-dedupe order and no
mapping is recorded. The probe itself is untouched by
this: sortprobe/selfprobe on a doubled playlist still
refuse, because the probe's oracle is a rotation
classification, while dedupe's oracle is verify-after on
the actual desired order. The daily run attempts
trial-dedupe only when the daily playlist's probe refused
on duplicate entries specifically.

## Stable preparation (v3.0.4)

Stable name: v3.0.4. Daily time: 8:00 AM, matching v2.6. The
installer records `3.0.4`. No tag or release is created by
this tree itself; publishing is a separate, explicit step.

```bash
bash setup-python.sh                     # install + 8:00 AM daily run
bash setup-python.sh --no-daily          # install only, no schedule
bash setup-python.sh --hour 9            # install + daily run at 9:00 AM
bash setup-python.sh --uninstall         # remove Python schedule + install dir
bash migrate-to-python.sh --dry-run      # print the migration plan, change nothing
bash migrate-to-python.sh --confirm      # disable v2.6 daily job, enable Python job
bash migrate-to-python.sh --rollback     # restore the v2.6 daily job
```

Installer facts: local files only, nothing downloaded; new install
dir `~/Documents/SeTeRShufflePython`; new plist label
`com.seter.python.daily`; the daily hour lives in exactly one place
(`DAILY_HOUR`/`DAILY_MINUTE` at the top of `setup-python.sh`).
Daily facts: `daily.sh` writes a daily library manifest (kept 14
days), auto self-probes both targets, then dedupes, shuffles,
and refreshes "SeTeR Rediscover"; it still REFUSES without a
fresh (<48h) per-target mapping for each target after the
self-probes, and a failed self-probe fails the run closed
before any build. The former stable-prep gaps are closed in
the drop-in package: `./run.sh menu` (Terminal menu; it
pre-checks the target's mapping and refuses before any dump
when none is recorded, and a blank size no longer crashes on
macOS bash 3.2), a
"Last reshuffled" playlist description stamp after verified
shuffle/flow applies (best-effort, never fails the apply),
macOS notifications on success and failure, `./run.sh shuffle
[size]` (100/250/500/1000/all, whole-library only), and dedupe
lines naming every removed duplicate. Flow energy flatness for
gospel-heavy libraries was fixed on the synthetic profile in
the 2026-10-29 flow-fix entry (arc-first walk, finer vibe
score); it is not claimed fixed against Spencer's real library
until the Step 10d flowPreview run on a Mac shows a rising
arc.
Migration facts: v2.6 script, backups, apps, and history are never
deleted or edited; only the v2.6 plist is renamed to
`.disabled-<timestamp>` on `--confirm`, and `--rollback`
restores it. Rediscover history carries over as-is because the
Python run reads the same file.

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
  (which aborts everything); run.sh records that mapping
  PER-TARGET, with the throwaway name and a user-declared sort
  label, and requires a fresh one (48 hours) before every apply
  and undo. A mapping measured on one playlist's sort NEVER
  transfers to a playlist with a different sort: the 2026-10-29
  15:38 PT Flow runs proved it, using the main playlist's
  reversed (descending) mapping for the new, default-sorted
  SeTeR Flow playlist and failing verification, correctly.
  Flow needs its own sortprobe on a throwaway set to SeTeR
  Flow's sort (see BRIDGE-SAFETY.md modes 35 and 36).
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
before) is a vibe score, not a tempo: base 50, an expanded genre
map (gospel/christian/worship -2, latin/reggaeton +6,
afrobeats/reggae +4, soundtrack -3, old groups unchanged), plus
group-8 genre subgroups (choir/choral -4, worship/praise -2,
contemporary +3), finer tiered plays (0/1/2/3/4/6/8/10/12 across
0/1/2-3/4-7/8-14/15-24/25-39/40-69/70+ plays), rating (3 stars +2,
4-5 stars +5, 1-2 stars -10), favorited +5, finer skip bands
(>90% skips -8, >50% -5, 25-50% -2, never-skipped well-played
+2), a release-year era band (2020+ +2, 2010s +1, 2000s 0,
1990s -1, older -2), and played-date recency plus date-added
newness when a clock is supplied. Skip-heavy songs stay eligible;
they just do not score like never-skipped ones. The fallback
spread is deliberately narrower than the BPM range: without a
tempo, these are weak signals, and a wide spread would be
guessing a tempo, not measuring one. The walk is arc-first:
genre cost 0/3/8 and year cost 0/2/4, plus +4 for repeating the
exact previous energy, so the arc target drives the walk and
genre continuity only breaks near-ties (the old 0/8/20 genre
cost outweighed the whole energy distance and flattened the
first half into one cluster). On a gospel-heavy synthetic
profile mirroring Spencer's library, the old walk gave a
16-long run of exactly 50 then a cliff to 72-77; the fixed
walk rises gradually and falls, with 16 distinct energies in
the first 25. That synthetic result is not proof against his
real library: the Mac flowPreview step in
STABLE-PROMOTION-TESTS.md must show a rising arc before this
is claimed fixed.

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

Tested here, for real (141 tests, all passing):

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
per-run backup chain, the sort-probe mapping deletion on
failure, and the restore command, plus the .3 mapping-gate
error visibility, plus the .5 per-target mapping guard and
the undo/restore -1728 empty fallback (161 tests total):
failures in `mapping_for_build` and
`probe_mode` (both called inside `$(...)`) now go to the log
file AND stderr via `logerr()`, never to stdout, so a refused
build shows its `GATE FAILED` line on the terminal instead of
stopping silently after "compute shuffle order" (the .2
behavior) or polluting the captured mapping (the .1 bug).
The Mac checklist that gates any stable promotion is
`STABLE-PROMOTION-TESTS.md`: sortprobe, sort controls,
title-sorted abort with a visible refusal, dedupe, failure
safety, negatives, flow, rediscover-preview, and restore, all
on throwaways first, real playlist only with explicit approval.

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
`./run.sh selfprobe "<target>"` (v3.0.2, preferred: the target
itself, under its own sort), or `./run.sh sortprobe
"<throwaway>" "<target>" "<sort-label>"` on a throwaway set to
the target's sort (Playlist Order descending for the 2026-10-28
failure), which must return a forward or reversed mapping and
restore the probed playlist; an "other" mapping aborts
everything by design. The mapping is recorded for that target
only; a build for any other target refuses until that target
has its own probe. The old `./run.sh probe` (fresh 3-song probe) is a
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
