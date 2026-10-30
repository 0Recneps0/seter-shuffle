# Stable-promotion test checklist (Mac, Spencer-run)

This is the gate between the experimental Python build and any stable
promotion. Nothing here runs on the real playlist until every
throwaway step below passes, and the real playlist is touched only
with Spencer's explicit approval after that. The bridge cannot be
executed anywhere except on a Mac with the Music app, so these steps
are the proof; the Python tests run on Linux prove the core only.

## Proven already (do not re-prove, do not skip the rest)

- 2026-10-29 12:44 PT: sortprobe on the real playlist measured
  `MAPPING: reversed`, and `./run.sh shuffle "My New Sandwich
  Recipe"` applied 806 songs in exact order under the reversed
  mapping, `APPLY OK`, backup verified. That proves the sort theory
  end to end for a descending-sorted playlist.
- What it does NOT prove: throwaway controls (ascending, manual,
  title), undo, restore, dedupe, flow, rediscover, negatives, or
  any of the .3 changes. Those are below, and they still gate
  promotion.

## Setup (do this once, before step 1)

1. Use ONLY the exp-2026-10-29.3 folder you unzipped. Do not reuse
   the old `.4`, `.5`, or `probe-2026-10-28` folders, and do not
   reuse the `.2` folder: `.2` hides mapping-gate failures from the
   terminal (see step 5).
2. In Terminal, `cd` into the unzipped folder (its root contains
   `run.sh`, `bridge/`, and `seter_shuffle/`).
3. Check the interpreter first:
   ```bash
   ./run.sh audit
   ```
   Pass: it prints the python path and version and exits without
   touching Music. If it fails, stop: Python is the problem, not
   the bridge.
4. Pause playback in Music before every build step. Leave
   throwaways on manual sort except when a step explicitly says
   otherwise.
5. Make throwaways in Music first, each with 5 or more DISTINCT
   songs (no duplicates inside a throwaway unless a step says
   doubled):
   - `SeTeR Test Desc` — set its sort to Playlist Order,
     descending, exactly like the real playlist.
   - `SeTeR Test Asc` — set its sort to Playlist Order, ascending.
   - `SeTeR Test Title` — set its sort to Title.
   - `SeTeR Test Manual` — leave on manual sort.
   - `SeTeR Test Double` — add each of 5 songs twice (10 entries).
   Write down the first and last song of each throwaway before
   you start; you will compare against them after undo/restore.

## Stage 0 — sortprobe

### Step 1: sortprobe on a descending throwaway
```bash
./run.sh sortprobe "SeTeR Test Desc"
```
Pass: output contains `MAPPING: reversed` (or `forward`) AND
`SORTPROBE_OK`, and the throwaway's songs are back in exactly
their pre-probe order (first/last match your notes, count
unchanged). Fail: any other mapping, or the throwaway changed.
If this step fails, stop. Do not run any build.

## Stage 1 — sort controls (shuffle, then undo, exact both ways)

For each throwaway, note the order before, run the shuffle, check
the order changed and the count is unchanged, then undo and check
the order is back exactly.

### Step 2: descending throwaway
```bash
./run.sh shuffle "SeTeR Test Desc"
./run.sh undo "SeTeR Test Desc"
```
Pass: shuffle applies with `APPLY OK` and exact-order
verification; undo restores the exact pre-shuffle order
(first/last and full sequence as shown in Music). This is the
control that must pass on the new code.

### Step 3: ascending throwaway
```bash
./run.sh shuffle "SeTeR Test Asc"
./run.sh undo "SeTeR Test Asc"
```
Pass: same as step 2, exact order both ways.

### Step 4: manual throwaway
```bash
./run.sh shuffle "SeTeR Test Manual"
./run.sh undo "SeTeR Test Manual"
```
Pass: same as step 2, exact order both ways.

### Step 5: title-sorted throwaway must abort untouched
```bash
./run.sh sortprobe "SeTeR Test Title"
```
Pass: the mapping is `other`, no build runs, and the throwaway
is completely untouched (same songs, same order, same count).
Then, WITHOUT running another sortprobe, try a build and
confirm the new .3 behavior:
```bash
./run.sh shuffle "SeTeR Test Title"
```
Pass: the run refuses BEFORE touching Music, AND the refusal
is VISIBLE on the terminal as a `GATE FAILED` line naming the
missing mapping (this is the .3 fix: in .2 this failure only
went to the run log file, so a shuffle looked like it just
stopped after "compute shuffle order"). Fail: silence on the
terminal, or any change to the throwaway.
After step 5, re-run step 1 to restore a usable mapping before
continuing.

## Stage 2 — dedupe, failure safety, and the other modes

### Step 6: dedupe on a doubled throwaway
```bash
./run.sh dedupe "SeTeR Test Double"
```
Pass: the throwaway ends with each song exactly once, in
first-occurrence order (the first copy's position wins), count
halved (10 to 5 in the suggested setup), and the run log says
the dedupe applied. No songs lost, no songs invented.

### Step 7: dedupe again on the clean throwaway
```bash
./run.sh dedupe "SeTeR Test Double"
```
Pass: the run reports no duplicate entries and applies
NOTHING. The throwaway is byte-for-byte unchanged. A rebuild
of an already-clean playlist is pure risk for zero gain, so
this must be a no-op.

### Step 8: a failing apply must not touch the main backup
This is a negative test, done on a throwaway only. The
simplest honest version: run a shuffle on `SeTeR Test Desc`,
then, before undoing, copy the main backup file for that
playlist out of `~/Library/Logs/seter-shuffle-python/` and
record its checksum:
```bash
shasum -a 256 ~/Library/Logs/seter-shuffle-python/backup-SeTeR_Test_Desc-*.txt
```
Then run a build that is forced to fail (for example, quit
Music mid-apply on a throwaway only, or use a corrupted order
file if you are comfortable doing so) and re-run the checksum.
Pass: the main backup file is byte-identical, and a new
per-run snapshot file (`backup-...run-*.txt`) exists in the
same directory. Fail: the main backup changed after a failed
run. If you cannot force a failure cleanly, skip this step
and mark it skipped in the record below rather than faking it.

### Step 9: negative suite (throwaway only, one at a time)
Each of these must refuse BEFORE deleting or duplicating
anything, leaving the throwaway untouched:
- empty order (not directly runnable from run.sh; skip unless
  you construct one by hand, and mark it skipped if so)
- ambiguous playlist name: two playlists with the same name
- smart playlist as the target
- the Library itself as the target
- undo with the backup file moved away (expect a refusal
  naming the missing backup and listing recent backups)
Pass for each: refusal with a visible error, throwaway
unchanged. Any silent proceed is a fail.

### Step 10: flowPreview and flow on a throwaway
```bash
./run.sh flowPreview
./run.sh flow
./run.sh undo "SeTeR Flow"
```
Pass: `flowPreview` prints a 50-song order and changes
nothing; `flow` builds `SeTeR Flow` with `APPLY OK`; undo
restores it. Note the energy spread in the preview: if
energies are still almost all exactly 50, that is a data
problem (missing BPM / unmapped genres), not a bridge bug,
and it goes back as Flow feedback, not a bridge failure.

Missing-playlist flow (.4, failure mode 34): delete
`SeTeR Flow` in Music first, then run `./run.sh flow`
under a fresh sortprobe mapping. Pass: it creates the
playlist and applies exactly with `APPLY OK`, no -1728 at
the snapshot step. Then run `./run.sh flow` again on the
now-existing playlist: pass is a clean refresh with
`APPLY OK`. A -1728 on either run is a fail; undo
afterwards to restore the pre-flow state.

Flow needs its OWN sortprobe (.5, failure mode 35): a
mapping measured on one playlist's sort NEVER transfers to
a playlist with a different sort. Before any `./run.sh flow`
run, run `./run.sh sortprobe "<throwaway>" "SeTeR Flow"
"<sort-label>"` on a throwaway set to SeTeR Flow's sort
(default/manual sort for a new playlist), and confirm the
GATE lines print the SeTeR Flow target and that sort label.
Pass: a flow attempt with only a main-playlist mapping
present refuses for lack of a SeTeR Flow mapping, and flow
after its own sortprobe applies exactly with `APPLY OK`.
A build for any other target must likewise refuse without
its own per-target mapping.

Flow arc on the real library (flow fix): run
`./run.sh flowPreview` on the real library and read the
first 25 energies. Pass: a rising arc, not a flat 47-50
block, with several distinct values in the first 25 and no
long run of one identical energy. Fail: the first 25 still
sit at 47-50, or the list jumps straight from the 40s to
the 70s with nothing in between. This step is what proves
the synthetic fix against Spencer's real library; do not
claim Flow fixed until it passes here.

### Step 11: rediscover-preview
```bash
./run.sh rediscover-preview
```
Pass: prints Rediscover picks, changes nothing, writes no
history. Do NOT run `./run.sh rediscover` in this checklist
unless you actually want the `SeTeR Rediscover` playlist
rebuilt; if you do, undo it afterwards with
`./run.sh undo "SeTeR Rediscover"`.

### Step 12: restore from an explicit backup file
```bash
./run.sh shuffle "SeTeR Test Manual"
./run.sh restore "SeTeR Test Manual" ~/Library/Logs/seter-shuffle-python/backup-SeTeR_Test_Manual-*.txt
```
Use the actual backup filename shown in the run log (the
glob above is a placeholder; pick the per-run or main backup
for that playlist). Pass: the throwaway returns to the
backup order exactly, verified by first/last and sequence.

## Stage 3 — real playlist (only with explicit approval)

Do NOT start this stage because the throwaway steps passed.
Spencer must explicitly approve it, in chat, after seeing the
record below.

1. Fresh read-only diagnostic on `My New Sandwich Recipe`
   first (count and first/last songs), because its state since
   the 12:44 shuffle has not been re-measured.
2. The first real job is a backup-order restore check, NOT a
   shuffle: confirm what undo/restore would return to, and
   that the backup on disk matches the playlist you expect.
3. Only after that check, a real shuffle may be considered,
   under a fresh (<48h) sortprobe mapping.

## Record (fill in as you go)

| Step | Result (pass / fail / skipped) | Date and time | Notes (counts, first/last, log lines) |
| ---- | ------------------------------ | ------------- | ------------------------------------- |
| 0 setup / audit | | | |
| 1 sortprobe descending | | | mapping: |
| 2 descending shuffle + undo | | | |
| 3 ascending shuffle + undo | | | |
| 4 manual shuffle + undo | | | |
| 5 title abort + visible refusal | | | |
| 6 dedupe doubled | | | |
| 7 dedupe clean no-op | | | |
| 8 failed apply backup intact | | | |
| 9 negatives | | | |
| 10 flowPreview / flow / undo | | | |
| 10b flow into missing playlist (.4) | | | |
| 10c flow's own sortprobe (.5) | | | mapping for SeTeR Flow only, never the main playlist's: |
| 10d flow arc on the real library (flow fix) | | | first 25 must rise, not sit at 47-50: |
| 11 rediscover-preview | | | |
| 12 restore from backup file | | | |
| Stage 3 approval | | | approved by: |

If any step fails: stop, paste the tail of
`~/Library/Logs/seter-shuffle-python/run.log`, and do not
proceed to the real playlist. A failed step is a result, not
something to work around by running the old code or the
retired fix script (never run `seter-fix-playlist.applescript`
on any playlist).

## Stable-preparation state (built on experimental, NOT yet proven on a Mac)

The following gaps are now BUILT on the experimental branch but
still UNPROVEN on a Mac, so they do not yet clear promotion.
Nothing here merges to main, and no stable release or tag exists
until Spencer approves the exact change list.

- Installer: BUILT (`setup-python.sh`, local-copy only, new
  install dir `~/Documents/SeTeRShufflePython`, version marker
  `3.0-proposed`, idempotent, refuses a different version
  without `--force`, never touches the v2.6 install or job).
  UNPROVEN: no installer run on a Mac yet.
- Launchd daily schedule: BUILT (`daily.sh` + plist
  `com.seter.python.daily`, proposed 8:00 AM matching v2.6,
  time in one place as `DAILY_HOUR`/`DAILY_MINUTE` in
  `setup-python.sh`). UNPROVEN: no launchd daily run on a Mac
  yet, and the daily run refuses without fresh (<48h)
  per-target mappings for both the daily playlist and "SeTeR
  Rediscover". v3.0.2 closes the manual-probe part of that gap
  with daily auto self-probes (see the v3.0.2 steps below);
  the mapping gate itself stays.
- Version naming: PROPOSED v3.0 (major bump: AppleScript to
  Python, and the mapping model changed). Recorded as a
  proposal in the installer (`3.0-proposed`); no v3.0 tag or
  release exists. Spencer's approval of the exact change list
  is still required before any stable publish.
- Migration: BUILT (`migrate-to-python.sh`: `--dry-run` default
  changes nothing, `--confirm` disables `com.seter.daily` by
  renaming its plist to `.disabled-<timestamp>` and loads the
  Python job, `--rollback` restores it; v2.6 script, backups,
  apps, and history are never deleted or edited; Rediscover
  history carries over as-is). UNPROVEN: no migration or
  rollback run on a Mac yet.
- Stable v2.6 stays intact as the fallback throughout. A
  stable promotion must leave a working way back to v2.6,
  not overwrite it in place. This package preserves that:
  separate install dir, separate plist label, rollback script.

## Stable-prep Mac steps (run AFTER the throwaway checklist above, before any stable publish)

1. Install only, no schedule, from the latest experimental
   folder: `bash setup-python.sh --no-daily`. Pass: files land
   in `~/Documents/SeTeRShufflePython`, version marker reads
   `3.0-proposed`, and the v2.6 install and `com.seter.daily`
   are untouched.
2. Re-run the installer: pass is idempotent (same files, same
   marker, no error). Then schedule: `bash setup-python.sh`
   (8:00 AM). Pass: `com.seter.python.daily.plist` exists with
   Hour 8, and `com.seter.daily.plist` still exists untouched.
3. Daily dry check (v3.0.2): `bash daily.sh "My New Sandwich Recipe"`
   with no fresh mappings must auto self-probe both targets
   first and then proceed: pass is manifest written, dedupe
   no-op or clean, shuffle APPLY OK, rediscover APPLY OK,
   history recorded. A daily run whose self-probe fails must
   refuse before any build and change nothing.
4. Migration dry-run: `bash migrate-to-python.sh --dry-run`
   must change nothing. Only with Spencer's explicit approval:
   `--confirm`, then verify the v2.6 job is disabled (plist
   renamed to `.disabled-*`) and the Python job is loaded.
   Then `--rollback` must restore the v2.6 job exactly, and a
   second `--confirm` must switch back. Do not leave the Mac
   migrated at the end of testing unless Spencer says so.
5. Remaining throwaway checklist items still owed before any
   stable publish: throwaway shuffle+undo, dedupe on a doubled
   throwaway, negatives, flow undo (see the record table
   above). A successful installer/daily/migration test does
   NOT replace those.

## Drop-in Mac steps (run after the stable-prep Mac steps, before any stable publish)

1. Menu: `./run.sh menu`, choose shuffle on a throwaway.
   Pass: the mapping-status line prints before the build, and
   the build applies (or refuses cleanly without a mapping).
   Menu blank-size step (mode 39 regression): choose shuffle
   on a throwaway with a blank size. Pass: no unbound-variable
   error, the shuffle computes and applies. Menu no-mapping
   step: choose shuffle on a target with no mapping recorded.
   Pass: the menu refuses with the sortprobe command BEFORE
   any dump, and returns to the menu.
2. Stamp: after a throwaway shuffle or flow, check the
   playlist description in Music. Pass: it reads
   "Last reshuffled: <date/time>"; if Music exposes no
   settable description, the log must say the stamp was
   skipped and the apply still succeeded. Undo must not
   change the description.
3. Notifications: run a throwaway shuffle and a failing
   build (e.g. without a mapping). Pass: a macOS notification
   appears for each, and a denied/unavailable Notification
   Center logs "notification unavailable" without failing
   the run.
4. Size: `./run.sh shuffle 100` must fill "SeTeR Shuffle"
   with exactly 100 songs; `./run.sh shuffle <throwaway> 100`
   must refuse before any dump.
5. Dedupe names: dedupe a doubled throwaway. Pass: the log
   names every removed duplicate by artist and title.
6. 48h daily precondition (v3.0.2 superseded): the daily run
   now auto self-probes each morning, so no evening probe is
   needed. The 48h mapping freshness gate still applies at
   build time: a 47h-old mapping passes, a 49h-old one
   refuses (test by hand with the recorded timestamps, do not
   wait two days if a faster check works); in normal daily
   operation the fresh self-probe mapping makes this moot.

## One-click Mac steps (v3.0.1)

1. Fresh or update: download the stable zip, unzip, double-click
   `SeTeR-Shuffle-Install.command`, answer yes once. Pass: the
   install dir lands at `~/Documents/SeTeRShufflePython` with
   marker `3.0.1`, the 8am `com.seter.python.daily` plist exists
   and is loaded, and the v2.6 plist is renamed to
   `.disabled-<timestamp>` (script and backups untouched).
   An update from a `3.0-proposed` or `3.0` install must succeed
   and keep differing files as `.bak` copies.
1b. One-click no-argument regression (v3.0.1): run the installer
   with no --playlist/--hour/--minute/--force arguments, exactly
   as the v3.0 run that died at Step 1 with an unbound-variable
   error on macOS bash 3.2. Pass: it proceeds past Step 1, with
   no unbound-variable error and no empty-array expansion.
1c. Stripped modes: if the unzipped helpers arrive mode 660
   (no execute bit), double-clicking must still work, because
   the installer chmods +x its own helpers at the start of a
   run. Pass: no "permission denied" from the entry point.
2. Decline: answer anything but yes. Pass: nothing changes.
3. Rollback: `bash ~/Documents/SeTeRShufflePython/migrate-to-python.sh --rollback`.
   Pass: the v2.6 plist is restored and loaded, the Python
   install stays in place.
4. First scheduled run (v3.0.2 supersedes the throwaway
   precondition): the daily run now auto self-probes both
   daily targets itself. Pass: the daily run proceeds with no
   manual probe in the previous 48 hours; a run whose
   self-probe fails must refuse before any build, never
   shuffle blind.

## Self-probe and daily auto-probe Mac steps (v3.0.2)

1. Self-probe on a clean target: `./run.sh selfprobe
   "<target>"` on a playlist with distinct entries. Pass: it
   returns a forward or reversed mapping, records THROWAWAY as
   the target name and SORT as "self-probe: target's own
   sort", and the target's order in Music is unchanged
   afterwards (snapshot restored and verified). A following
   build on that target must apply under the self-probe
   mapping with no throwaway involved.
2. Daily auto-probe: run `daily.sh` by hand with no manual
   probe in the previous 48 hours. Pass: the log shows an
   auto self-probe OK for the daily playlist AND for "SeTeR
   Rediscover" before the mapping check, then manifest,
   dedupe, shuffle APPLY OK, rediscover APPLY OK.
3. Other-mapping abort: self-probe a target whose sort is not
   buildable (e.g. a title-sorted playlist, if Music lets
   the probe run on it). Pass: the probe returns "other",
   deletes that target's mapping, changes nothing else, and
   no build runs for the target until its sort changes and a
   clean self-probe passes.
4. Restore from snapshot after a failed probe restore: this
   is hard to stage deliberately; if a self-probe ever
   reports that its restore could not be verified, pass is:
   the target's snapshot path is named in the log, the
   measured mapping is still recorded, `./run.sh restore
   "<target>" "<snapshot>"` returns the target to its
   pre-probe order, and no build runs until a clean
   self-probe passes afterwards.
5. Doubled-playlist deadlock (expected failure, not a bug):
   self-probe a doubled playlist. Pass: it refuses on
   duplicate entries, changes nothing, and the daily run
   fails closed on that target. Dedupe it by hand (or under
   a mapping obtained another way) before it can be
   auto-probed; do not weaken the refusal to get past this.

## Stable-promotion gaps STILL open (not fixed by this prep package)

- Flow energy flatness for gospel-heavy libraries: left
  open deliberately (see the changelog drop-in entry). No
  dump field justifies a wider spread without inventing a
  tempo.
- No one-click .app bundle: the menu is Terminal-based,
  stated plainly, not hidden.
- Main-playlist state on the Mac (dedupe method/count)
  was still unconfirmed when this package was built; a daily
  auto run needs a clean per-target mapping for the main
  playlist, and sortprobe refuses a doubled playlist.
