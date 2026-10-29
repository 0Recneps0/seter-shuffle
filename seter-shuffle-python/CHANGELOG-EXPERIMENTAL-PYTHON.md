# Experimental changelog, Python core

This file tracks the Python experimental build only. Stable releases
(v2.6 is current stable) are untouched by anything here, and so is the
AppleScript experimental build. The Python version is published, if at
all, as a prerelease, never as stable, and is never auto-installed on
a Mac. The daily stable run stays AppleScript.

## 2026-10-29 — Delete-empty verification, dedupe, and a full runner sweep (sixth Python change, after a third real failure)

**Why:** on 2026-10-29 at 00:41 PT Spencer ran the OLD .5 code
again (a second download folder, not the sort-aware .1 build) on
the real playlist, and the dump counted 1612 songs: the playlist
had doubled between the 00:21 diagnostic (806 songs) and the
00:41 run to exactly two copies of each song, backup =
reverse(original) twice, pre-undo snapshot = original twice. The
.5 apply and undo then failed verification in the same loop. The
`.prev` backup (13701 bytes) still equals the original 806-song
order, and Spencer says he has his own backup playlist, so
recovery is not urgent — but the script must be fixed, and this
build also sweeps every other open issue in BRIDGE-SAFETY.md and
INVESTIGATION-2026-10-28.md instead of only the two named items.
NOT PUBLISHED YET: this tree is unreviewed by the parent and
unproven on a Mac; nothing here has been pushed by this build
(the parent creates the release).

**What changed (all in `seter-shuffle-python/`, nothing else):**

- Delete-empty verification, in apply-order, undo,
  restore-original, and sort-probe (new `deletePlaylistSongs`
  handler in each): delete, re-read, confirm 0 song entries,
  retry up to 5 times with a 5-second settle delay; if entries
  remain, return the `delete-not-empty` sentinel and duplicate
  NOTHING. Callers restore from the verified backup (apply) or
  the pre-undo snapshot (undo) only if the playlist was actually
  changed (a partial delete), and report "playlist unchanged" if
  it still matches the backup/snapshot exactly. The doubling
  mechanism itself (delete lagging at 806-song scale) is
  UNPROVEN: the guard does not depend on it, and if no throwaway
  reproduces the lag, the guard stands as prevention, not as a
  proven root cause. Bulk reads (`playlistIDs`, `librarySize`)
  are now inside 3600-second timeout blocks like the build loops.
- Dedupe command: `./run.sh dedupe <playlist>` dumps one
  playlist, computes unique songs in first-occurrence order
  (`seter_shuffle/order_direction.py::dedupe_ids`, plus the CLI
  `dedupe` command), validates it with a new `dedupe` mode
  (exactly the dump's unique set, each ID once; a repeat, a drop,
  or an invented ID refuses), then applies it through the SAME
  safe rebuild path (snapshot backup, delete-empty verification,
  sort-aware duplicate, exact verify, restore on failure).
  Dedupe forces the bridge duplicate allowance to "0" (its order
  is unique by construction). If the playlist holds no
  duplicates, run.sh applies NOTHING (no rebuild of a clean
  playlist). Documented everywhere it matters: dedupe preserves
  first-occurrence order in the current list-read order, NOT the
  original backup order, so on a reversed doubled playlist it
  yields unique songs in reversed order and a backup-order
  restore is still a separate step afterwards.
- Runner bug fix, found by code review (BRIDGE-SAFETY.md mode
  31): the .1 runner's `mapping_for_build` logged with `log()`
  (tee to stdout) while every caller captures it with `$(...)`,
  so every captured mapping carried a log line and the bridge
  refused it. **No .1 build through run.sh could have run at
  all** (direct osascript calls with a clean mapping word would
  have worked, but run.sh is the documented path). Fixed by
  logging with `logfile()` only inside `mapping_for_build`, and
  guarded by a structural test that extracts the function body
  and refuses any `log ` call in it. The fix was verified by
  extracting the .2 function verbatim and capturing it to
  exactly `[reversed]` (the .1 function captured to a polluted
  two-line string in the same harness).
- Backup chain (BRIDGE-SAFETY.md mode 32): the 00:41 run
  overwrote the main backup with the doubled state, and only
  `.prev` saved the original; one more failed run would have
  overwritten `.prev` too. `apply_order` now writes the
  pre-change snapshot to a fresh per-run file
  (`<backup>.run-<timestamp>-<pid>.txt`), installs it as the
  main backup ONLY after a verified successful apply (previous
  main backup preserved as `.prev`), and keeps the newest 10
  per-run snapshots. On apply failure the restore attempt uses
  the per-run snapshot and the log states the main backup was
  NOT overwritten. Undo never writes to the main backup path.
- Stale-mapping and restore gaps (mode 33): a sort-probe failure
  now DELETES the recorded mapping file (and writes it atomically
  on success), so a failed re-probe cannot leave an old mapping
  in place for a build under an unknown sort. New
  `./run.sh restore <playlist> <backup-txt>` gives
  restore-original the same freshness-checked gate as undo;
  direct osascript calls remain possible and remain ungated on
  freshness by construction, and the docs now say so plainly:
  use run.sh, never call a bridge script directly for a build.
  `run.sh undo` refuses before anything is deleted when the main
  backup file is missing, listing recent backups instead.
- Sort-probe "other" aborts now report the throwaway's state in
  words (restored to snapshot vs left holding the rotation
  order), not just a boolean, and run.sh's sort-probe failure
  path names the throwaway snapshot file to check.
- Undo, apply, and restore parity, checked by re-reading all
  three: every run.sh path reads the recorded mapping fresh
  (<24h), forward/reversed only, passes it identically, and the
  bridge scripts each refuse any other mapping string before
  resolving anything. No run.sh path builds without a mapping,
  and no bridge script builds with an "other" mapping. The one
  remaining bypass is direct osascript invocation (freshness
  only, not mapping presence), documented as expert-only above.
- Mac procedure updates (BRIDGE-SAFETY.md Stage 2): dedupe on a
  doubled throwaway, dedupe again on the clean throwaway (must
  apply nothing), a failing apply must leave the main backup
  byte-identical, and a failed sort-probe must make the next
  build refuse for lack of a mapping.
- Tests: 128 passed, 0 failed here (101 previous + 27 new in
  `tests/test_delete_empty_and_dedupe.py`: dedupe order
  computation including the reversed-doubled shape, dedupe
  validation file and in-memory, CLI dedupe on dump files
  including the empty-playlist nonzero exit, and structural
  guards for the delete-empty handler in all four scripts, the
  logfile-only mapping reader, the per-run backup chain, the
  sort-probe mapping deletion, and the restore command). Shell
  syntax of run.sh checked with `bash -n`.

**Still unproven on a Mac (honest list, with the test that would
prove each):** every AppleScript change above, as before; the
delete-lag mechanism itself (a throwaway whose delete can be
shown to lag, or a doubled throwaway deduped cleanly, proves the
guard, not the mechanism); the sort-matched mapping end to end
(sortprobe on a descending throwaway, then descending/ascending/
title controls, then negatives, then dedupe on a doubled
throwaway, real playlist only at Stage 3 with Spencer's explicit
approval); the per-run backup chain under a real failing apply;
the size-ladder and selection-context and duplicate-copy tests
from INVESTIGATION-2026-10-28.md step 5, which no throwaway run
has yet performed and which could still implicate a property
beyond sort; and whether the current doubled real playlist's
state matches the last snapshots (a fresh read-only diagnostic
is still owed before any real-playlist step). Nothing here
claims any of that is proven.

## 2026-10-29 — Sort-matched build mapping replaces the fresh probe (fifth Python change, after a second real failure)

**Why:** on 2026-10-28 at 23:46 PT the .5 bridge was run on the
real playlist "My New Sandwich Recipe" (806 songs) again, skipping
the throwaway stages. Its fresh 3-song probe reported "forward" on
all channels, yet apply failed verification and restore failed,
and undo failed the same way, exactly as in .4. The backup taken
at the start of the .5 run equals the original backup exactly, and
the pre-undo snapshot is again the EXACT REVERSE of the original
backup, 806/806, same set. No song left the library. The user
then confirmed the missing property: the real playlist is sorted
in Music by playlist order DESCENDING, which no fresh probe
playlist shares. A read-only diagnostic on 2026-10-29 then killed
the draft sort design (classify by comparing the every-track list
against the track-index order): the current list read is the exact
reverse of the original backup by its ends, positional first/last
agree with the list, and the list's first track carries index 1,
which no "list is reverse of manual index order" story predicts.
So index is not a manual-order reference on this Music version,
and both the fresh probe and any index classification are dead.
NOT PUBLISHED: this tree is unreviewed by the parent and unproven
on a Mac; nothing here has been pushed.

**What changed (all in `seter-shuffle-python/`, nothing else):**

- New `bridge/sort-probe.applescript`: the only direction
  authority for builds. It takes a throwaway the user has set to
  the target's sort, snapshots it atomically, builds a rotation
  of its order (items 2..n plus item 1; for 5+ distinct songs
  neither the snapshot order nor its reverse), reads it back,
  and classifies the end-to-end mapping: "forward" (read ==
  build), "reversed" (read == exact reverse of build), or
  "other" (anything else: another column sort, a partial build,
  or unpredictable behaviour). It then restores the throwaway
  under the measured mapping and verifies that restore; a failed
  restore is a hard error naming the snapshot file. It requires
  at least 5 distinct song IDs, refuses ambiguous names and
  non-user playlists, and never touches any other playlist.
- `run.sh`: new `./run.sh sortprobe <throwaway>` command that
  runs the sort-probe, parses its `MAPPING:` line, and records
  the mapping with the throwaway name and a timestamp in the
  state dir (valid 24 hours). Apply and undo now read that
  recorded mapping and refuse without a fresh one; they pass the
  mapping (not a probe mode) to the bridge scripts. The old
  `probe` / `probe-keep` commands stay as standalone sanity
  checks only and are consulted by no build.
- `bridge/apply-order.applescript`, `bridge/undo.applescript`,
  and `bridge/restore-original.applescript`: all converted to
  mapping-only. The mapping argument is required (old probe-mode
  strings fail loudly). Build/verify formulas: to land list-read
  order D, duplicate D under "forward" and reverse(D) under
  "reversed"; verification always compares the list read
  against D. Restore uses the same formulas with D = the backup
  order. An "other" mapping refuses before any change. There is
  no flip on a failed verify anywhere: restore from backup and
  exit non-zero. The retired 2026-10-28 one-off fix script on
  the user's Mac (`~/Downloads/seter-fix-playlist.applescript`)
  must still never be run; the rewritten tree file is a
  different, mapping-based script and is itself unproven.
- `bridge/diagnose-playlist.applescript`: header only. It now
  states explicitly that track index is NOT a manual-order
  reference and must never be used as a classification input.
  Its printed lines are unchanged.
- `bridge/probe-order.applescript`: header only. It is now
  marked retired from builds; no build may wire it back in.
- `seter_shuffle/order_direction.py`: legacy probe-mode
  functions kept and marked legacy; the mapping section
  (`parse_mapping`, `mapping_from_build_result`,
  `build_for_mapping`, `expected_for_mapping`) is the single
  source of truth for the formulas, mirrored by the AppleScript
  handlers `buildForMapping` / `verifyAgainst`. The
  Python sort-classification functions from the discarded first
  design were removed, and their test file deleted.
- `tests/test_sort_mapping.py`: 14 tests covering mapping
  classification (including the rotate probe-order unambiguity
  point), the forward/reversed build formulas, the
  verify-expectation-is-desired invariant, a reversed round-trip,
  and the restore formula with the real backup ends (first
  `B49A108A0E5553DB`, last `54BC5E32EB0D0F8E`).
- `BRIDGE-SAFETY.md`: new failure mode 30 at the top (sort
  mechanism, exact-reverse evidence, why the .5 probe missed it,
  why index classification was discarded, the abort behaviour,
  and the falsifiers), audit item A1 updated to the confirmed
  model, the .5 probe section marked superseded, and the Mac
  procedure rewritten: Stage 0 is now the read-only diagnostic
  plus a full-dump comparison, the UI sort check, the
  sort-matched sort-probe gate, and the throwaway sort controls
  (descending must fail on old code and pass on new code,
  ascending/manual must pass, title-sorted must abort
  untouched); Stage 3 is a real playlist only with explicit
  user approval after seeing Stage 0-2, plus a display eyeball
  after any restore. Nothing touches "My New Sandwich Recipe"
  before Stage 3.
- `README-PYTHON.md`: bridge description and suggested Mac
  verification order rewritten around sort-probe and the
  mapping gate.

**Still unproven on a Mac:** every AppleScript change above.
The Mac procedure in BRIDGE-SAFETY.md is the proof plan, in
order, throwaways first. The restore goal the bridge can
measure is list-read order == backup order; whether the
display follows it is a Stage 3 eyeball check, not something
any script proves.

## 2026-10-28 — Probe-driven order direction (fourth Python change, after a real failure)

**Why:** on 2026-10-28 the .4 bridge was run straight on a real
playlist, "My New Sandwich Recipe" (806 songs), skipping the
throwaway stage. Apply, its restore, and undo all failed exact-order
verification in a loop. No song left the library. The two backup files
pulled off that Mac prove the inside of the loop: the pre-undo
snapshot is the EXACT REVERSE of the original backup (806/806 same
unique IDs, reversed; re-verified from the files, not taken on
faith). Either duplicating inserts at the top of a playlist, or the
every-track read returns tracks reversed; the backup files alone
cannot tell which. The user later said the playlist "looks normal",
which is consistent with both mechanisms ending back at the original
display after the full chain, and proves nothing about exact order
for 806 songs. This change replaces guessing with a probe. NOT
PUBLISHED YET: this tree is unreviewed by the parent and unproven
on a Mac; nothing here has been pushed.

**What changed (all in `seter-shuffle-python/`, nothing else):**

- New `bridge/probe-order.applescript`: creates a 3-song probe
  playlist, duplicates in a known order, and reads it back by the
  every-track list, by each entry's `index` property (sorted
  ascending), and by positional first/last tracks. Verdict is
  "forward", "insert-reversed", or "read-reversed" only when the
  channels agree on one model; anything else is "ambiguous". The
  probe deletes its own playlist (and on error paths too) unless
  run with "keep" for the manual eyeball check. The positional read
  travels through the same scripting bridge as the list read, so it
  is a contradiction check only, never the sole basis for a
  direction; the manual eyeball step in BRIDGE-SAFETY.md is the only
  truly independent read. If the `index` property is unavailable,
  the probe reports ambiguous (fail-closed), never a guessed mode.
- New `seter_shuffle/order_direction.py`: the testable mirror of the
  bridge's mode formulas. An apply build wants a display order O
  (duplicate O, except insert-reversed duplicates reverse(O);
  verify against O, except read-reversed verifies against
  reverse(O)). Every restore build wants to return to a list-read
  snapshot T (duplicate T under "forward", reverse(T) under either
  reversed mode; verify against T in all modes). Apply, undo, and
  restore-original carry handlers with the same names and the same
  formulas; if they ever drift from this module, the bridge is
  wrong even though the Python tests pass.
- `bridge/apply-order.applescript` and `bridge/undo.applescript`
  rewritten around the mode: the mode argument is REQUIRED (an old
  unprobed call fails loudly before anything changes); every build,
  verify, and restore uses the mode formulas; there is NO
  flip-on-failure fallback in either script. Build and restore loops
  run inside `with timeout of 3600 seconds` blocks (the .4 build
  took ~2 minutes for 806 songs). Apply's argument order changed:
  mode, then duplicate flag, then optional whole-library song count
  (run.sh no longer passes a playlist dump's count as a library
  count; see below).
- `bridge/restore-original.applescript` rewritten: its default path
  now probes (mode "auto") or takes an explicit probed mode, and
  builds/verifies with the mode formulas. The old flip logic
  survives ONLY as explicit "flip" mode, documented as
  throwaway-only, because under read-reversed it rebuilds an
  already-correct playlist in reverse order and calls that a
  success. Never run the 2026-10-28 version of that script again,
  and never run "flip" on a real playlist.
- `run.sh` probes before every apply and undo (probe_mode, fresh
  timestamped probe playlist per run); an ambiguous or failed probe
  aborts with the real playlist untouched. New `./run.sh probe`
  (measure and report) and `./run.sh probe-keep` (leave the probe
  playlist for the eyeball check, then delete it by hand). Undo and
  apply-failure restores pass the same probed mode to undo.
  Backup filenames now also neutralize newlines/carriage returns.
  One-playlist shuffles pass --allow-duplicates to the CLI and the
  duplicate allowance flag to apply (see below); whole-library
  dumps pass the library count as before.
- Duplicate-entry playlist shuffles now work instead of failing
  closed (audit item A14): load_library gains allow_duplicates
  (CLI --allow-duplicates, passed by run.sh only for one-playlist
  shuffles); validate-order's shuffle check is now multiset
  equality and its duplicate rule is "no more copies than the
  dump"; apply-order's duplicate check is skipped only under the
  allowance flag. Whole-library orders still refuse any repeat.
- `bridge/dump-library.applescript`: jsonEscape rewritten as a
  character loop that escapes every control character as \u00XX
  (audit item A16); the old version left non-standard control
  characters raw, which made the JSON unparseable and stopped the
  run fail-closed.
- `BRIDGE-SAFETY.md`: failure mode 29 (the reversal, with the
  evidence and both mechanisms), the probe and its honest limits,
  a full further-audit table (A1-A20: UI sort settings, iCloud
  sync, now-playing track, cloud-only tracks, ID changes, non-song
  entries, timeouts, mid-run duplicate names, the .4 library-count
  argument bug, backup filename characters, stale dumps, order
  JSON/text gaps, dump order vs display order, the .4 duplicate
  refusal, .4 hardening re-check, dump escaping, CLI --size,
  validate-backup inconsistency, the old flip script, probe
  parsing), and a rewritten Mac procedure starting with Stage 0
  (probe, then eyeball the kept probe playlist) and forbidding any
  real playlist before Stage 3.
- Tests: 86 passed, 0 failed here (67 previous + 19 new in
  tests/test_probe_mode.py: mode formulas in all modes including
  empty/single/duplicate inputs and input immutability, multiset
  shuffle validation, load_library duplicate modes, CLI playlist
  shuffle with and without --allow-duplicates, probe verdict
  parsing, and structural presence checks for the probe script and
  mode handlers). Shell syntax of run.sh and check-python.sh
  checked with `bash -n`.

**What the Mac run must prove now (bridge constructs, all unverified):**

- The probe itself, first: `./run.sh probe` reports one of the three
  modes with PROBE_CLEANUP_OK, and `./run.sh probe-keep`'s on-screen
  probe playlist order in Music matches that verdict. If the verdict
  is ambiguous, or the eyeball disagrees with it, STOP and report
  both: no build should proceed on that verdict.
- Whether the track `index` property is exposed on playlist tracks
  in this Music version (if not, every probe is ambiguous by design).
- Then the full throwaway procedure in BRIDGE-SAFETY.md (Stage 1
  happy path including a duplicate-entry playlist, Stage 2 negative
  tests, Stage 3 a real playlist you can afford to have rewritten,
  Stage 4 the force-quit case on a throwaway only). Nothing in this
  build has run on a Mac, including the probe, the mode formulas in
  AppleScript, the new jsonEscape loop, and the timeout wrappers.

**Known limits (honest list):**

- The bridge cannot be executed here (no osascript, no Music), so
  nothing in `bridge/` has run at all. Treat it as reviewed, not tested.
- The probe's positional read is not independent of its list read
  (same scripting bridge); the manual eyeball step is the only
  truly independent check, and it is required, not optional.
- Direct apply/undo calls without a mode argument now fail loudly
  by design; only run.sh (or an explicit probed mode) can drive them.
- The old one-off fix script's flip behaviour is preserved only
  behind explicit "flip" mode for throwaways; the 2026-10-28 version
  must not be run again.

## 2026-10-28 — AppleScript bridge hardening (third Python change)

**Why:** Spencer asked for the bridge to be made extremely
bulletproof: no way for songs to be deleted or duplicated, make it
perfect, take your time. This change is the bridge only; the core
ordering logic is untouched.

**What changed (all in `seter-shuffle-python/`, nothing else):**

- New `seter_shuffle/validate.py` plus `validate-order` and
  `validate-backup` CLI commands: the same refuse rules as the
  bridge, applied in Python before osascript ever runs. Empty
  orders, duplicate IDs, IDs missing from the dump, shuffle orders
  that are not exactly the dump's song set, truncated orders (the
  text file must agree exactly with the order JSON, including its
  count), malformed/non-UTF-8 files, and expected-count mismatches
  are all refused with the problem listed. Backups are validated
  too, with duplicates allowed and an empty backup valid (it
  snapshots an empty playlist).
- `bridge/apply-order.applescript` rewritten with a safety header:
  target resolved by filtered lookup (0 = create, >1 = refuse as
  ambiguous, 1 = use that object); `assertUserPlaylist` refuses the
  Library, smart playlists, and anything that is not a regular user
  playlist, failing closed if any check cannot be performed; order
  validated before any change (strict read, empty refusal,
  duplicate check via `sort | uniq -d`); backup written atomically
  (temp file, `mv -f`, re-read and compared exactly) before any
  delete, never truncated in place; build collects lookup failures
  instead of silently skipping; any build, verify, or library-shrink
  failure restores from backup and exits non-zero; verify-after is
  an exact ID-list comparison, not a count check; verification
  itself is wrapped so Music quitting during verify also restores;
  the restore handler never throws from its own verify step.
- `bridge/undo.applescript` rewritten with a safety header: backup
  validated before anything is deleted; target resolved by filtered
  lookup and never created; current playlist snapshotted first to
  `<backup>.pre-undo` (atomically written and verified) so a failed
  undo is recoverable; rebuild collects failures; any rebuild,
  missing-song, or verification failure restores the pre-undo
  snapshot and exits non-zero; empty backup restores an empty
  playlist; backup duplicates reproduced exactly; non-song entries
  never deleted.
- `bridge/dump-library.applescript` hardened: filtered playlist
  resolution (ambiguous names refused); required lists must all
  have exactly n entries or the dump aborts unwritten, so a mid-read
  library change cannot misalign values onto the wrong tracks;
  the bulk-read helper no longer pads to full length (that bug had
  made its count check dead code and blocked the `favorited` to
  `loved` fallback, which now actually runs); output written
  atomically (temp file, `mv -f`, non-empty check), so a failed
  write never leaves a half-written dump.
- `run.sh` rewired: a `step()` helper logs GATE OK / GATE FAILED
  for every step and sends both stdout and stderr to the log, so
  the log proves which gate fired; `validate-order` runs after the
  core computes an order and before any apply; the dump's song
  count is passed to apply as its library-shrink argument; any
  previous backup is preserved as `<backup>.prev` and the backup
  path cleared before an apply, so a stale backup can never be
  mistaken for a fresh one; on apply failure with a fresh backup,
  the runner attempts a restore via undo before exiting non-zero,
  and with no fresh backup it logs that the playlist was not
  changed; history is still recorded only after a successful apply.
  Backup filenames now include a hash of the playlist name, so two
  names differing only by spaces and slashes no longer share a
  backup file (old backup files remain usable by direct osascript
  call).
- `check-python.sh` now refuses loudly if the interpreter path
  contains a space, since run.sh splits its output on the first
  space.
- New `BRIDGE-SAFETY.md`: the full failure-mode table (mode, old
  behaviour, new guard, how to test it on a Mac), the uncovered
  case and its recovery, and the exact Mac verification procedure
  (throwaway playlist first, then a real one, then undo, checking
  counts and exact order at each step).

**What was actually tested here (Linux VM, Python 3.12.3):**

```bash
python3 -m unittest discover -s tests
# Ran 67 tests in 0.577s — OK
bash -n run.sh check-python.sh && echo shell-ok
# shell-ok
```

67 passed, 0 failed (41 pre-existing, all still passing, plus 26
new in `tests/test_bridge_safety.py` covering every validation
rule: empty, duplicate, missing ID, shuffle count/set mismatch,
blank middle line, whitespace ID, order-JSON disagreement
including a truncated text file, expected-count mismatch, flow and
rediscover ineligible IDs, non-UTF-8 and malformed files, backup
missing/corrupt/empty/duplicates, and both CLI commands' return
codes).

**What was NOT tested here, and is not claimed:** every Music
interaction in the bridge scripts. This machine has no Music app
and no osascript, so no bridge script has been executed. Proof
here is line-by-line review (including a grep confirming the only
Music deletes target asserted user playlists, never
`library playlist 1`) plus the Python tests above. The Mac
verification procedure in `BRIDGE-SAFETY.md` is still required,
and no bridge script should be called proven until it has been
run. The one case AppleScript cannot fully cover is also stated
without softening in that document: power loss or force-quit
mid-write cannot run a restore; recovery is re-running undo from
the verified backup file in the state directory.

**Not published:** nothing in this change has been pushed or
released. That decision is for the parent agent.

## 2026-10-28 — Missing-BPM fallback and tag audit (second Python change)

**Why:** Spencer ran `./run.sh flowPreview` on his Mac on 2026-10-28:
940 songs dumped, 938 eligible, 50-song preview, nothing changed,
but almost every energy was exactly 50 (one at 55). The old model
defaulted missing BPM to 50 and his gospel/Christian genres matched
no genre group, so the walk had nothing to climb with.

**What changed (all in `seter-shuffle-python/`, nothing else):**

- New `audit` command (`python3 -m seter_shuffle.cli audit --library
  dump.json`, and `./run.sh audit` on a Mac): counts and percentages
  for BPM present vs missing vs zero, genre present vs missing, the
  most common raw genre strings with counts, played-count bands,
  rating bands, favorited, disliked, enabled, Flow eligibility, and
  the Flow energy spread. It changes nothing in Music. It is the
  diagnostic that separates "library truly lacks BPM" from "dump
  script fails to read BPM": some BPM present means the dump works
  (a dump bug loses BPM for the whole list at once, via the bulk-read
  fallback); zero BPM present means suspect the dump first.
- Missing-BPM energy fallback, with BPM-present songs scoring
  exactly as before (same BPM bands, same legacy genre nudges, same
  single >=20 plays step, same rating/favorited): base 50, expanded
  genre map (gospel/christian/worship/praise -2, latin/reggaeton +6,
  afrobeats/reggae +4, soundtrack -3, old groups unchanged), tiered
  plays (1-4 +2, 5-19 +4, 20-49 +6, 50+ +9), rating (3 stars +2,
  4-5 stars +5, 1-2 stars -10), favorited +5, and a -5 skip penalty
  only when at least 3 plays+skips exist and more than half were
  skips. Skip-heavy songs stay Flow-eligible; the penalty is a
  score, not an exclusion. Clamp stays 5..100.
- Tie-breaking in the greedy walk: on an exact cost tie, prefer a
  genre group different from the previous pick, then higher
  familiarity (plays capped at 100, +25 favorited, +rating stars),
  then the earliest pool song. Deterministic; flat-energy pools no
  longer come out in raw library order.
- `run.sh` gains `./run.sh audit` (dump, then audit, no apply, no
  history write). `README-PYTHON.md` gains the audit commands, a
  section explaining why BPM is not attached to every song, and the
  fallback model in plain words.

**Answer to the question behind this change:** no, not every song in
Apple Music has a BPM attached. Music does not analyse tempo: the BPM
field comes from the track's own metadata and is often blank,
especially for rips, older files, and sources that never wrote a
tempo tag. That is a metadata gap, not a bug in the shuffle, and the
fallback above is built for exactly that case.

**Before/after, on a varied 10-song missing-BPM fixture (run here):**

- Before: 50, 65, 63, 58, 58, 38, 55, 50, 65, 50 — 6 distinct
  values, three songs stuck at exactly 50.
- After: 48, 64, 64, 58, 55, 38, 57, 50, 69, 60 — 9 distinct
  values over 38-69, with only the truly blank song (unknown genre,
  no plays, no rating, not favorited) still at 50.
- The fallback spread is deliberately narrower than the BPM range:
  without a tempo, plays and genre are weak signals, and a wide
  spread would be guessing a tempo, not measuring one.

**What was actually tested here (Linux VM, Python 3.12.3):**

```bash
python3 -m unittest discover -s tests -v
# Ran 41 tests in 0.541s — OK
```

41 passed, 0 failed (31 pre-existing, all still passing, plus 10
new). New coverage: audit counts matching the sample fixture
(including BPM zero vs missing), audit CLI leaving the fixture
untouched, the missing-BPM spread, gospel/Christian/worship/praise/
latin/afrobeats/soundtrack mapping, BPM-present parity (including a
gospel BPM track scoring exactly as before), the skip penalty
applying only without BPM, skip-heavy songs staying Flow-eligible,
and the tie-break being deterministic. Shell syntax of `run.sh` and
`check-python.sh` checked with `bash -n`.

**What the Mac run must prove (still unverified):**

- `./run.sh audit` on Spencer's real library: the BPM present
  percentage and the top raw genres. If BPM present is 0%, the dump
  script is the prime suspect, not the library. If it is a small
  non-zero share, the library really lacks BPM and the fallback is
  the right fix. The top genres list also tells whether the new
  genre map covers what he actually has, or needs another pass.
- `./run.sh flowPreview` after the fallback: energies should spread
  instead of clumping at 50, and the arc should visibly rise and
  fall. If they still clump, the audit's genre/plays data will show
  why (for example, if his plays and ratings are also mostly blank).
- Everything from the first build's unverified list (bridge scripts,
  runner end to end, undo) remains unverified: no Mac run of those
  has happened from here.

## 2026-10-28 — Python core, first build (based on v2.6 + Flow)

**What it is:** the shuffle, Rediscover, and Flow logic rewritten in
Python (standard library only) as a testable core, plus a thin
AppleScript bridge that is the only part talking to Music. Same
defaults, same safety idea, same models as the AppleScript builds;
the difference is that the logic can actually be executed and tested
on a machine without Music.

**What was built:**

- `seter_shuffle/` — settings (v2.6 + Flow defaults), track model and
  library-JSON loading (duplicate persistent IDs rejected, unparseable
  dates treated as missing), artist keys (featuring counts as the main
  artist), Fisher-Yates shuffle with the v2.6 artist-spacing repair
  pass, Rediscover eligibility/weights/sampling (liked x forgotten,
  favorited x3, 4-5 stars x2, 1-2 stars x0.25, divided by 1+skips,
  forgotten multiplier capped at 5x, max 3 per artist, 14-day cooldown
  with relax-then-fill passes, picks shuffled and artist-spread),
  Flow energy (BPM bands, genre nudges, plays/rating/favorited, clamped
  5..100), Flow genre groups and related pairs, the wave arc (45 start,
  90 peak at two-thirds, 40 end), and the greedy nearest-neighbour
  walk (energy distance + genre cost + year cost + 1000 spacing
  penalty, ties keep the earliest song).
- CLI (`python3 -m seter_shuffle.cli`): `shuffle`,
  `rediscover`, `rediscover-preview`, `flow`, `flowPreview`
  (plus `flow-preview` alias), and `record-history`. The core reads a
  library JSON dump and writes an ordered-ID JSON and/or a
  one-ID-per-line text file. Preview commands never touch Music and
  never write history; `rediscover` does not write history either.
- Bridge (`bridge/`): `dump-library.applescript` (read-only dump of a
  library or playlist to JSON, dates as ISO from date components),
  `apply-order.applescript` (backup file written BEFORE any change,
  build from library by persistent ID, verify count + every expected
  ID, restore on any failure, regular user playlists only, library
  shrink check), `undo.applescript` (replay a backup file, loud on
  partial restores).
- Runner (`run.sh`) and `check-python.sh`: the runner wires
  bridge -> core -> bridge, logs under
  `~/Library/Logs/seter-shuffle-python/`, records Rediscover history
  only after a successful apply, and fails before touching Music if
  no real python3 (3.9+) is found. `run.sh` never touches the stable
  install or its launchd job.
- Tests (`tests/test_core.py`, fixture `tests/fixtures/sample-library.json`).

**What was actually tested here (Linux VM, Python 3.12.3):**

```bash
python3 -m unittest discover -s tests -v
# Ran 31 tests in 0.542s — OK
```

31 passed, 0 failed. Coverage includes: missing BPM, missing genre,
0/1/2-song Flow, artist spacing, featuring handling, disliked and
unchecked exclusion (both modes), skip-heavy exclusion (Rediscover
only) versus inclusion (Flow), Rediscover max-per-artist and cooldown,
history roundtrips, Flow arc targets and tie handling, energy clamps,
and CLI previews proving the input file is left byte-identical.
Shell syntax of both scripts was checked with `bash -n`. Two genuine
bugs were found and fixed during this build: the CLI `__main__`
guard was placed before `main()` was defined, and the runner parsed
the check script's "path (version)" output as the interpreter path.
One test expectation was also corrected during review: with
spacing=2, at least 2 songs must sit between repeats, so two artists
alone can never satisfy it; the test now uses three artists and
asserts the best-effort contract (never increases clash count) instead
of an impossible separation.

**What the Mac run must prove (bridge constructs, all unverified):**

- Dump script: bulk reads of `bpm`, `year`, `played date`, and
  `date added` over a playlist reference; `favorited` with the `loved`
  fallback; `month as integer` and the date-component ISO formatting;
  JSON escaping of unusual metadata (quotes, backslashes, newlines).
- Apply script: `first track of library playlist 1 whose persistent
  ID is ...` lookup; that duplicating tracks in order actually yields
  that order in the playlist; the verify step (count + presence);
  restore from backup after a forced failure; refusal of smart
  playlists; behaviour when a wanted ID is missing from the library.
- Undo script: restoring a real playlist from a real backup file,
  including the empty-backup (first-run playlist) case.
- Runner end to end: `check-python.sh` against the Mac's actual
  python3 (including what the stub does on that machine),
  `flowPreview` output, a real `flow` apply, the run log, and undo.
- Cross-check: a Python Flow order and an AppleScript Flow order from
  the same library should agree closely (identical, given the same
  pool draw and seed handling, is not expected: the AppleScript pool
  draw and the Python pool draw use different random sources).

**Known limits (honest list):**

- The bridge cannot be executed here (no osascript, no Music), so
  nothing in `bridge/` has run at all. Treat it as reviewed, not tested.
- Python Flow and AppleScript Flow will not produce byte-identical
  orders from the same library unless the pool draws coincide; the
  models match, the random sources do not.
- The dump script's JSON escaping handles backslash, quote, newline,
  carriage return, and tab; exotic control characters in metadata are
  not specially escaped.
- Rediscover weights for songs dated in the future would go negative
  in theory; the core drops non-positive weights rather than feeding a
  negative weight into the cumulative sampler (v2.6's sampler would
  misbehave there too, and no real library should have future dates).
- The runner's backup filenames are derived from playlist names by
  replacing spaces and slashes with underscores; two playlists whose
  names differ only by those characters would share a backup file.
  Playlist names with newlines would also break the line-based
  interchange files. Both are edge cases, flagged here rather than
  hidden.
