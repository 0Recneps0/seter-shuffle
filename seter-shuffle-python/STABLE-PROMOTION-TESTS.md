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
   under a fresh (<24h) sortprobe mapping.

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
| 11 rediscover-preview | | | |
| 12 restore from backup file | | | |
| Stage 3 approval | | | approved by: |

If any step fails: stop, paste the tail of
`~/Library/Logs/seter-shuffle-python/run.log`, and do not
proceed to the real playlist. A failed step is a result, not
something to work around by running the old code or the
retired fix script (never run `seter-fix-playlist.applescript`
on any playlist).

## Stable-promotion gaps NOT resolved by this release

These must be resolved before any stable promotion, and none
of them is fixed by exp-2026-10-29.3:

- No installer for the Python build. `run.sh` only runs from
  inside the unzipped folder; it copies nothing anywhere and
  schedules nothing. Stable v2.6 ships `setup.sh` and a daily
  launchd run.
- No launchd daily schedule for the Python build, so there is
  no daily shuffle/Rediscover run to replace v2.6's 8am run.
- Version naming is undecided (v3.0, v2.7, or another number
  for the Python build as stable). Do not pick one by
  accident in a release title.
- Migration from the v2.6 AppleScript daily run is undesigned:
  what happens to the existing launchd job, the stable
  script, and the `SeTeRShuffleTemp` workflow on the Mac.
- Stable v2.6 stays intact as the fallback throughout. A
  stable promotion must leave a working way back to v2.6,
  not overwrite it in place.
