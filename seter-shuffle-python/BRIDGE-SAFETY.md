# Bridge safety: what cannot go wrong, and what still needs a Mac to prove

Status, stated plainly: **this document describes a reviewed design,
not a tested one.** The Python core and its validation were tested on
Linux (141 tests, all passing). The AppleScript bridge cannot run here:
this machine has no Music app and no osascript, so no bridge script
has ever been executed. Nothing below claims a bridge script works.
The Mac verification procedure at the end is what turns "reviewed"
into "proven", and until it has been run, treat the bridge as
unproven. That warning is stronger than it was for .4, because .4
was also "reviewed, not tested" and then failed on a real playlist
(see mode 29 below). Do not run this build on a real playlist first.

## Failure mode 29: playlist order comes back reversed (2026-10-28, real failure)

On 2026-10-28 the .4 bridge was run straight on a real playlist,
"My New Sandwich Recipe" (806 songs), skipping the throwaway stage.
The order computed and validated fine. Then apply, its internal
restore, and run.sh's undo restore ALL failed exact-order
verification in a loop (apply 23:12:47 to 23:14:50, undo 23:14:50 to
23:16:26). No song left the library. The two backup files pulled off
that Mac prove what happened inside the loop: the pre-undo snapshot
is the EXACT REVERSE of the original backup, 806/806 same unique IDs,
reversed. Re-verified from the files in this VM's uploads, not taken
on faith: counts 806 and 806, sets equal, pre-undo == reverse(original).

Two mechanisms explain that evidence equally well, and the backup
files alone cannot distinguish them:

  (a) insert-reversed: `duplicate track to playlist` inserts at the
      TOP of the playlist on that Music version, so duplicating in
      order lands reversed, while the every-track read is faithful.
  (b) read-reversed: duplicating appends normally, but `persistent
      ID of every track of playlist` returns tracks in reverse
      playlist order, so the read is reversed while the display is
      correct.

Both mechanisms also explain why the user later said the playlist
"looks normal": traced through the full chain (apply build, apply
restore, undo build, undo pre-undo restore), both end back at the
original display order. That does NOT prove the display is original
now: eyeballing cannot settle exact order for 806 songs, and any
step that behaved differently from the trace (a partial build, a
missing track) would break the symmetry. Never claim the current
playlist is reversed or original from this evidence; the evidence
proves a reversal happened somewhere in the chain, not what the
display is now.

SUPERSEDED 2026-10-29 BY MODE 30: this section describes the .5
probe design, which failed on the real playlist a second time
because a fresh probe playlist does not share the real playlist's
sort, and because its index channel is not a manual-order
reference. It is retained as history only. Builds now use the
sort-matched mapping (mode 30); the probe script is a standalone
sanity check and no build reads its verdict.

The fix is a PROBE, not a guess (bridge/probe-order.applescript,
wired into run.sh before every apply and undo). The probe creates a
3-song playlist, duplicates in a known order, and reads it back three
ways: the every-track list, the `index` property of each probe entry
(sorted ascending), and the positional first/last tracks. The verdict
is "forward", "insert-reversed", or "read-reversed" only when the
channels agree on one model; anything else is "ambiguous" and aborts
the run with the real playlist untouched. Apply, undo, and the
one-off restore script then build and verify with that mode's
formulas (seter_shuffle/order_direction.py, mirrored in AppleScript):
an apply build wants a display order O (duplicate O, except
insert-reversed duplicates reverse(O); verify against O, except
read-reversed verifies against reverse(O)), while every restore
build wants to return to a list-read snapshot T (duplicate T under
"forward", reverse(T) under either reversed mode; verify against T
in all modes). There is NO flip-on-failure fallback in apply or
undo: a failed verify restores and exits non-zero, because a wrong
flip on a real playlist is exactly the .4 bug.

Honest limits of the probe, stated plainly:

- The positional read travels through the same Music scripting
  bridge as the list read, so it is NOT an independent instrument.
  It is used only as a contradiction check: if it disagrees with
  both other channels, the probe is ambiguous. The two real channels
  are LIST and INDEX.
- If the bridge reversed everything consistently (list, index, and
  positional all reversed together), the probe would misclassify
  read-reversed as insert-reversed or vice versa. That residual risk
  is why the procedure below requires a manual eyeball step: run
  `./run.sh probe-keep`, look at the probe playlist in Music itself,
  and confirm the on-screen order matches the verdict before any
  real playlist is built with a probed mode. The on-screen order is
  the only truly independent read available.
- If this Music version does not expose the `index` property on
  playlist tracks, the probe reports ambiguous (fail-closed), never
  a guessed mode. That is a refusal, not a data loss.
- The previous one-off fix script's flip logic (bridge/restore-original.applescript
  as written on 2026-10-28) is UNSAFE under read-reversed: on a
  playlist that is already correct on screen, it reads backwards,
  decides a flip is needed, rebuilds in reverse order, and declares
  success on a playlist it just broke. That script has been
  rewritten twice since: first to the probe design above, then
  again on 2026-10-29 to mapping-only (a recorded sort-matched
  mapping is required; there is no probe path and no flip path in
  it at all). Never run the 2026-10-28 version of that script on
  any playlist again.

## Failure mode 30: sort-matched mapping replaces the fresh probe and the index model (2026-10-29, second real failure + diagnostic)

On 2026-10-28 at 23:46 PT the .5 bridge was run on the real playlist
"My New Sandwich Recipe" (806 songs) again, skipping the throwaway
stages. Its fresh 3-song probe reported "forward" on all channels,
yet apply failed verification and restore failed (~107 s), and
run.sh's undo restore failed verification and pre-undo restore
failed (~99 s), exactly as in .4. The backup taken at the START of
the .5 run equals the original .4 backup exactly, so the run started
from the original list-read order; the pre-undo snapshot taken
during its undo is again the EXACT REVERSE of the original backup,
806/806, same set. No song left the library in either run.

The user then confirmed the missing property: the real playlist is
sorted in Music by playlist order DESCENDING, which no fresh probe
playlist shares. That is why the .5 probe measured the wrong thing.
Then the user ran the read-only diagnostic on the real playlist:

  COUNT_SONGS: 806, COUNT_TRACKS: 806
  LIST_FIRST: 54BC5E32EB0D0F8E, LIST_LAST: B49A108A0E5553DB
  POS_FIRST: 54BC5E32EB0D0F8E, POS_LAST: B49A108A0E5553DB
  INDEX_OF_LIST_FIRST: 1

The original backup's first ID is B49A108A0E5553DB and its last is
54BC5E32EB0D0F8E, so the current list read is the EXACT REVERSE of
the original backup (ends confirmed; the diagnostic prints ends
only, so full exactness is a Stage 0 dump comparison, not an
assumption). Two consequences, both acted on in this build:

  1. A restore to the backup order is actually needed once a fix is
     proven, not just hypothetical. And "looks normal" is worth
     nothing as evidence: eyeballing 806 songs cannot settle exact
     order, and this diagnostic settles the list-read state where
     eyeballing could not. (Under a descending sort, a reversed
     list read can still DISPLAY in the original order, which is
     one more reason the display must be eyeballed after any
     restore; see the procedure.)
  2. Track index is DEAD as a manual-order reference, and the
     list-vs-index sort classification drafted for this build was
     discarded before publication for exactly this reason. If
     index were manual order and the list were sorted descending
     (reverse of manual), the list's first track would carry index
     806, not 1. So either index follows the current view (carrying
     no manual information) or the playlist's manual order itself
     is now reverse(B) and the list read is the manual order. The
     two readings cannot be told apart from index, so index is
     never used as a classification input anywhere in the bridge
     anymore. It is printed by the diagnostic as a reported value
     only. Any future design that classifies a sort from index is
     wrong on this evidence and must not be revived.

The replacement model measures ONE observable quantity on a
throwaway carrying the target's sort: the end-to-end build-to-list
mapping (bridge/sort-probe.applescript, seter_shuffle/
order_direction.py's mapping section). The user sets a throwaway's
sort in Music to the target's sort (Playlist Order descending for
this failure), sort-probe snapshots it, builds a ROTATION of its
order (items 2..n plus item 1, which for 5+ distinct songs is
neither the snapshot order nor its reverse), reads it back, and
classifies: "forward" (read == build), "reversed" (read == exact
reverse of build), or "other" (anything else: another column sort,
a partial build, or behaviour the bridge cannot predict). It then
restores the throwaway under the measured mapping and verifies
that restore; a failed restore is a hard error. run.sh records
the mapping with the throwaway name and a timestamp; builds
refuse without a mapping fresher than 48 hours, and pass it to
apply/undo/restore-original as a required argument.

Build/verify formulas, per mapping (desired list-read order D):
forward: duplicate D, verify list read == D. Reversed: duplicate
reverse(D), verify list read == D. Other: no build at all; the
sort-probe refuses upstream and the bridge scripts refuse the
string. There is no flip on a failed verify: restore from backup
and exit non-zero. Restore worked through concretely with B for
the original backup order and the current list read reverse(B):
a restore wants list read B again, so it duplicates B under a
forward mapping and reverse(B) under a reversed mapping, and that
statement holds under EITHER index reading above, because it
depends only on the measured mapping, never on what index means.
The restore goal the bridge can measure is the list-read order B;
whether the display follows it is a Stage 3 eyeball check, not
something any script proves.

What would kill this model (falsifiers, all checked in the
procedure, not assumed away):
  * A descending-sorted throwaway whose sort-probe returns
    "forward" and whose builds then pass, while the target still
    fails: the mapping would not be determined by the sort.
  * A sort-matched throwaway returning "other": the mapping is
    not forward/reversed for that sort, and no build may proceed.
  * The Stage 0 full dump showing the current list is NOT the
    exact reverse of the backup (ends match by coincidence): the
    restore target and the failure story both need rework.
  * A descending-sorted throwaway passing on the OLD (.5) code:
    the sort would not explain the original failures, and the
    whole sort theory would be dead, not just the mapping.
  * The diagnostic showing list == index order on the real
    playlist despite the reported descending sort, with a full
    dump confirming it: the list would not follow the sort at
    all, and the mapping would need a different explanation.

The fresh-probe script (bridge/probe-order.applescript) and its
`./run.sh probe` command remain as a standalone manual sanity
check only. No build reads a probe verdict, so a probe verdict can
never override a sort-matched mapping; the disagreement case the
.5 design worried about cannot arise in a build path, because the
build path has no probe input. That is deliberate, not an
oversight: the only direction authority is the sort-matched
mapping, recorded by sort-probe.

## Failure mode 31: run.sh captured a log line into the mapping (2026-10-29, runner bug found by code review, not by a Mac run)

The .1 runner's `mapping_for_build` logged its success line with
`log()`, which tees to stdout, while every caller captures its
output with `$(mapping_for_build)`. The captured "mapping" was
therefore a two-line string (a timestamped log line, then the real
mapping word), which every bridge script's `parseMapping` refuses
before anything changes. Proven here, not assumed: a harness
extracting the .1 function verbatim and capturing it produced
`[2026-10-29 ... sort mapping for builds: forward ...\nforward]`,
not `[forward]`. Consequence, stated plainly: **no build through
run.sh could have run at all under .1** — every apply and undo
would have failed at the mapping argument, playlist untouched. A
direct osascript call with a clean mapping word would have worked,
but run.sh is the documented path, so .1 was effectively
unrunnable, not merely unproven. The fix is in run.sh only:
`mapping_for_build` now logs with `logfile()` (log file only),
never `log()`, and a structural test extracts the function body
and refuses any `log ` call in it. The fix was re-verified the
same way: the .2 function extracted verbatim captures to exactly
`[reversed]`. The probe_mode function already had this discipline
(logfile-only inside command substitution); mapping_for_build was
the one place it was missed, which is why the test now guards the
function text rather than trusting the pattern.

**Update in .3:** the logfile-only rule for failures overshot in
the other direction: a missing or stale mapping made a shuffle
stop after "compute shuffle order" with no visible error, because
the failure reached only the log file. Failures in
`mapping_for_build` and `probe_mode` now go through `logerr()`
(log file AND stderr, never stdout, since stderr is never
captured by $(...)); success info stays logfile-only. The mode
31 table row below still describes the .1/.2 history; the
current rule is logerr-for-failures, and
`tests/test_mapping_stderr.py` guards it (failure on stderr
with empty stdout, valid mapping capturing exactly).

## Failure mode 32: a failed run overwrote the only good backup (2026-10-29, real failure)

The 00:41 run on 2026-10-29 took its pre-change snapshot from a
playlist that had already doubled (1612 entries) and wrote it to
the main backup path, overwriting the original 806-song backup.
Only the `.prev` copy (the previous run's backup, preserved by the
runner before clearing the path) still held the original order,
and one more failed run would have overwritten `.prev` with the
doubled state too: a chain of length one is not a safety net, it
is a countdown. The snapshot itself was not wrong — a backup is a
pre-change snapshot, and the pre-change state really was doubled —
but letting a failed run destroy the last good state is. The fix
is in run.sh's `apply_order`, and it changes backup semantics:
the apply script now writes its snapshot to a fresh per-run file
(`<backup>.run-<timestamp>-<pid>.txt`), never to the main backup
path. Only after a verified successful apply is that file
installed as the main backup (previous main backup preserved as
`.prev`), and the per-run file is kept, not deleted: the newest
10 per-run snapshots form a chain. On an apply failure, the
restore attempt uses the per-run snapshot, and the log says
explicitly that the main backup was NOT overwritten. Undo never
writes to the main backup path at all (it writes only the
`.pre-undo` snapshot), and `run.sh undo` now refuses before
anything is deleted if the main backup file is missing, listing
recent backups instead of letting the script discover it after a
delete. What this does NOT fix: if the playlist is already
corrupted before a run, the per-run snapshot faithfully records
the corrupted state — that is correct snapshot behaviour, and the
recovery for it is the chain (an older per-run snapshot, or the
user's own backup playlist), not the newest file. Never assume
the newest backup is the good one; check it against a known state
before restoring from it.

## Failure mode 33: stale mapping, un-gated restore, and missing-backup undo (runner gaps, fixed in run.sh)

Three smaller runner gaps, all fail-closed now:

  * A failed sort-probe used to leave a previously recorded
    mapping in place. A re-probe that returns "other" means the
    current sort is unknown, so a build under the old mapping
    would be building under an unverified sort. A sort-probe
    failure now DELETES the recorded mapping file and logs that
    it did, so the next build refuses until a clean sort-probe
    passes. The mapping file is also written atomically
    (temp file + rename) on success.
  * `restore-original.applescript` had no run.sh path, so its
    only invocation was a direct osascript call, which bypasses
    the 24-hour mapping freshness check by construction: a script
    cannot know when its mapping argument was measured. There is
    now `./run.sh restore <playlist> <backup-txt>`, which checks
    the backup file exists and the mapping is fresh before
    calling the script, exactly like undo. Direct osascript calls
    to any bridge script remain possible and remain ungated on
    freshness; the rule is now written down, not implied: never
    call a bridge script directly for a build, use run.sh. The
    scripts still require a mapping argument and refuse anything
    but forward/reversed, so a direct call cannot build
    unmapped, only stale-mapped.
  * Undo, apply, and restore now share the exact same gate
    sequence in run.sh: recorded mapping, fresh (<48h),
    forward/reversed only, passed identically to the bridge
    script, and the bridge script's own parseMapping refusal as
    the second check. No run.sh path builds without a mapping,
    and no bridge script builds with an "other" mapping.

## Failure mode 34: flow into a playlist that does not exist yet fails at the first bulk read (2026-10-29, real failure)

On 2026-10-29 Spencer ran `./run.sh flow "SeTeR Flow"` from
the .3 folder. Flow compute and validation passed, but apply
failed with AppleScript error -1728: "Can't get persistent ID
of every track of user playlist id 78940 ... whose media kind =
song", in the `playlistIDs` bulk read. Safety worked: no
per-run snapshot was written, the playlist was untouched, and
the main backup was untouched. Spencer then confirmed the
target playlist did not exist yet in Music, so the failing path
is: `resolvePlaylist(allowCreate=true)` creates the playlist
via `make new user playlist`, and the next bulk filtered read
on that freshly created (empty) playlist fails. Two mechanisms
could produce that, and the Mac evidence cannot distinguish
them: the make-new return value going stale (Music / iCloud
sync re-identifying the new playlist), or the filtered bulk
read itself failing on a brand-new empty playlist. The fix
covers both, and does not depend on which one it was:

  * After creating a playlist, apply-order re-resolves it by
    id with a fresh lookup (`first user playlist whose id is
    newID`) and builds only from that reference. A failed
    fresh lookup aborts before anything changes.
  * `playlistIDs` now falls back on a bulk-read error to an
    unfiltered track count: count 0 proves the snapshot is
    empty and returns {}, anything else rethrows, because a
    snapshot for a non-empty playlist must never be guessed.
  * `deletePlaylistSongs` applies the same fallback to its
    empty re-read: a filtered-count error plus an unfiltered
    count of 0 counts as verified empty, so a fresh empty
    playlist passes a gate it already satisfies. A filtered
    error with tracks present still fails, since song vs
    non-song entries cannot be told apart in that case.

Audit result for the same pattern elsewhere: only apply-order
creates a playlist on a build path. Undo, restore-original,
and sort-probe resolve existing playlists and refuse when
missing. The retired standalone probe-order script also creates
its own throwaway (and deletes it afterwards); its
`playlistIDs` carries the same empty fallback for
consistency, though it only ever reads a 3-song playlist.

This fix is UNPROVEN on a Mac like every other bridge change:
the -1728 diagnosis rests on Spencer's confirmed missing
playlist plus the error text, and the fresh-lookup plus
count-0 fallback must be proven by the Mac test below before
any flow into a missing playlist is trusted.

## Failure mode 35: a mapping measured on one playlist's sort is used for a playlist with a different sort (2026-10-29, real failure)

On 2026-10-29 at 15:38 PT Spencer ran `./run.sh flow "SeTeR
Flow"` twice from the .4 folder. Both runs: flow compute and
validation passed, then apply failed verification ("final song
order does not match the desired order under mapping
reversed"), apply restored from the per-run snapshot, and then
run.sh's restore via undo failed (mode 36). State files on his
Mac prove: both SeTeR Flow per-run snapshots are 0 bytes (the
playlist was empty at apply start), no main SeTeR Flow backup
was ever installed, and the recorded mapping was "reversed",
measured on throwaway "My New Sandwich Recipe" at 13:13 PT.

The apply failure is NOT a -1728 failure and NOT a snapshot
failure. The .4 create-then-read fix worked for the snapshot
(the empty fallback let the snapshot step succeed). The
failure is mapping transfer: the .4 runs used the reversed
mapping measured on the main playlist, which is sorted
Playlist Order descending, for a NEW target playlist, SeTeR
Flow, whose sort is the default/manual sort. A reversed build
on a forward-sorted playlist lands backwards, so verify
correctly refused. Under .4 there was one shared mapping
file, so nothing stopped a Flow build from silently reusing a
shuffle build's mapping.

The rule, stated explicitly because .4 violated it by
omission: a mapping measured on one playlist's sort NEVER
transfers to a playlist with a different sort. The worked
example is Flow itself: main playlist, Playlist Order
descending, mapping reversed; new SeTeR Flow playlist,
default/manual sort, mapping forward (to be measured, not
assumed). run.sh cannot read a playlist's UI sort from Music,
so the enforcement is structural, not observational:

  * Mappings are per-target files, keyed by target name plus
    a hash (`mapping_file_for`, same scheme as backups). A
    build for target X reads ONLY X's file.
  * `mapping_for_build` takes the target, validates the
    file's TARGET field matches, and requires a non-empty
    SORT field and a fresh (<48h) timestamp.
  * The pre-.5 shared `sort-mapping.txt` is IGNORED, never
    read as a mapping source; a build with only that file
    refuses with a message saying so.
  * `sortprobe` requires three arguments:
    `./run.sh sortprobe <throwaway> <target> <sort-label>`,
    and records MAPPING, THROWAWAY, TARGET, SORT, and
    TIMESTAMP in the per-target file. The sort label is
    user-declared: the user confirms the throwaway is set to
    the target's sort, and the label is what later GATE
    lines print.
  * apply/undo/restore print the recorded sort label and
    throwaway in their GATE lines (`mapping_info_for`, via
    log(), never captured), so a mismatch is visible before
    building.
  * A failed sort-probe deletes ONLY that target's mapping
    file.

This fix is UNPROVEN on a Mac, and cannot be proven without
a Mac run on a new-sort target: a Flow build must refuse for
lack of a SeTeR Flow mapping (it must NOT silently reuse the
main playlist's reversed mapping), and must succeed only
after its own sortprobe on a throwaway set to SeTeR Flow's
sort. Until that run, .5's guard is code-reviewed and
unit-tested here only.

## Failure mode 36: undo fails with -1728 on an empty playlist, and run.sh calls it "may be partial" (2026-10-29, real failure)

Same two 15:38 PT runs as mode 35. After apply restored from
the per-run snapshot, run.sh's restore via undo failed with
the same AppleScript -1728 bulk-read error ("Can't get
persistent ID of every track of user playlist id 78940 whose
media kind = song"). The .4 empty fallback went into
apply-order and the retired probe script, but NOT into
undo.applescript (and restore-original was the same).
Undo's first step is a bulk playlistIDs read on the target,
which fails with -1728 on the empty SeTeR Flow playlist, so
undo died before changing anything, and run.sh reported it
as "playlist may be partial" when nothing had changed. The
playlist was not partial; the restore step never started.

Fix, the exact same fallback as .4, applied everywhere it
was missing:

  * `bridge/undo.applescript` and
    `bridge/restore-original.applescript`: `playlistIDs`
    falls back on a bulk-read error to an unfiltered track
    count (0 returns {}, anything else rethrows), and
    `deletePlaylistSongs` falls back to the unfiltered count
    for its empty re-read. The pre-change snapshot read and
    atomic write are wrapped so a failure there rethrows
    with a PLAYLIST_UNTOUCHED marker ("playlist untouched").
  * `bridge/sort-probe.applescript`: the same playlistIDs
    and delete fallbacks.
  * `bridge/diagnose-playlist.applescript` (read-only): its
    bulk song-ID read is now guarded the same way; count 0
    reports empty, anything else errors as unreadable
    rather than guessing.
  * `run.sh`'s post-apply restore branch greps the log from
    the restore STEP line for the PLAYLIST_UNTOUCHED marker
    and logs "untouched, NOT partial" in that case, keeping
    the CRITICAL "may be partial" message for all other
    restore failures.
  * Audit of every `playlistIDs` handler: apply-order, undo,
    restore-original, sort-probe, and the retired probe-order
    all now carry an empty fallback. The one deliberate
    exception is `bridge/dump-library.applescript`, which has
    no playlistIDs handler; its bulk filtered reads on the
    library (940 songs, proven working) were left alone. A
    dump of an empty playlist could theoretically hit the
    same -1728, but it fails before any change and is not a
    build path that modifies anything.

This fix is UNPROVEN on a Mac like every other bridge change:
it needs a Mac run against an empty playlist (undo or
restore on a fresh empty throwaway) before it is trusted.

## Failure mode 37: a scheduled daily run with no fresh mapping (stable-prep gap, not a bridge bug)

The Python daily run (`daily.sh`, plist `com.seter.python.daily`,
proposed 8:00 AM) needs fresh (<48h) per-target mappings for both
its targets (the daily playlist and "SeTeR Rediscover"). Stable
v2.6's daily run needed no such step: it ran unattended every
morning. If the Python daily job runs on a day without a manual
sortprobe in the previous 48 hours, it refuses before touching
Music and logs which sortprobe to run by hand. That refusal is
correct under the current rules, but it means the Python daily
job is NOT yet a drop-in replacement for v2.6's daily job.
`daily.sh` deliberately never auto-probed a throwaway: an
automated probe would measure a throwaway whose sort nobody
just verified, which is exactly the mapping-transfer failure
of 2026-10-29 (mode 35). Do not "fix" this gap by
auto-probing a throwaway or by borrowing another target's
mapping. SUPERSEDED 2026-10-29 by mode 39: Spencer settled
the mapping rule himself (probe the target itself), and the
daily job now auto self-probes; the throwaway auto-probe ban
stands.

## Failure mode 39: automatic self-probing (2026-10-29, Spencer's correction)

Spencer corrected the throwaway-only rule: Apple Music
remembers each playlist's own sort, so probe the actual
target playlist itself, not a different throwaway. The
earlier ban on using the target as the throwaway was
over-cautious for sortprobe specifically (it still holds
for test shuffles: never shuffle a real playlist as a test).
A mapping measured on the target under its own sort is, by
construction, the mapping for that target and sort, so no
throwaway sort needs matching and no mapping transfer is
possible. That is also why an automated probe is safe in
this form when it was not as a throwaway probe (mode 37):
the self-probe's sort is the target's own, not an
unverified imitation of it.

Safety properties, unchanged except as noted:
- The probe snapshots the target first, builds a rotation
  (never the snapshot order nor its reverse, for 5+
  distinct songs), restores the snapshot under the measured
  mapping, and verifies the restore before returning OK.
  A failed restore leaves the target holding the rotation
  order, with the snapshot file named in the log,
  recoverable via `./run.sh restore <target> <snapshot>`.
- An "other" mapping is still an abort, never a build, and
  still deletes the target's mapping (the sort is then
  unknown). For a self-probe, "other" means the target's
  own sort is not one the bridge can build into.
- The duplicate-entry refusal is unchanged: a self-probe on
  a playlist with duplicate entries refuses and changes
  nothing. A currently doubled playlist (the main playlist
  was 1612 entries / 806 unique on 2026-10-29) therefore
  cannot be auto-probed until it is deduped by hand, or
  under a mapping obtained another way. The refusal is NOT
  weakened to work around that deadlock.
- One deliberate exception to "a failed probe deletes the
  mapping": a probe that measured forward/reversed but
  could not verify its own restore RECORDS that mapping,
  so `./run.sh restore` (which needs a fresh mapping) can
  run, while the probe still exits non-zero and no build
  follows until the target is restored and a clean probe
  passes. Every other probe failure still deletes it.
- `daily.sh` auto self-probes the daily playlist AND
  "SeTeR Rediscover" before the mapping check and before
  any build, in that order. A first-target probe failure
  stops the run before the second probe (the two probes
  share one snapshot file, `$STATE/sort-probe-snapshot.txt`,
  so a second probe would overwrite the snapshot needed
  to restore the first target) and before any build. The
  mapping gate itself is not dropped: after the probes,
  each target still needs a fresh, correctly-targeted,
  forward/reversed mapping.
- `run.sh` records a self-probe as THROWAWAY == target and
  SORT == "self-probe: target's own sort". A throwaway
  sortprobe with throwaway == target is the same self-probe
  (its sort label is replaced). The old throwaway form
  keeps working exactly as before, and a fresh throwaway
  probe is never used by any build or by the daily run.
- v3.0.3 extends the same auto self-probe to every other
  build path, closing the v3.0.2 gap Spencer hit in the
  menu: `run.sh` menu choices, and direct shuffle /
  rediscover / dedupe / flow / undo / restore, now call
  ensure_mapping_for before any dump or apply. A fresh
  mapping is reused with NO re-probe; a missing or stale
  mapping triggers ./run.sh selfprobe on the target
  itself, then a re-check; a failed probe aborts with
  the probe error named, before any dump or apply, and
  the menu loops back. Gate-failure messages no longer
  tell the user to run a manual sortprobe first when
  the automatic self-probe just failed; they name the
  self-probe that was attempted. The menu's old "never
  probes" rule is superseded: it auto-probes, and never
  overrides a refusal or borrows another target's mapping.

## Failure mode 40: trial-dedupe breaks the doubled-playlist deadlock (2026-10-29, proven on the Mac)

On 2026-10-29 18:44 PT Spencer ran the v3.0.3 menu on the
real main playlist and the auto self-probe refused on
duplicate entries (1612 entries, 806 unique), target
untouched, no dump or apply. Dedupe needs a mapping, and
the probe cannot measure one on a doubled playlist: that
is the deadlock mode 39 left open, and trial-dedupe
(v3.0.4) breaks it WITHOUT weakening the probe.

The distinction matters and must not be blurred later:
the probe classifies a sort from a rotation WITHOUT
changing the target's intended order, so a duplicate entry
makes its read-back ambiguous and it must refuse. Dedupe
changes the target to a KNOWN order (first occurrence of
each song) and checks the result, so its mapping oracle
is verify-after on that actual desired order, not a
rotation. Trial-dedupe therefore tries the deduped order
under mapping forward, verifies the list read against it,
and on failure restores from the per-run snapshot and
tries reversed. The first mapping that verifies wins and
is recorded as a trial-dedupe mapping (SORT label says
exactly that), so the next build reuses it directly. If
neither verifies (for example an "other" sort like Title
ascending), the playlist is restored to its pre-dedupe
order, no mapping is recorded, and dedupe exits non-zero.
If an attempt's restore itself fails critically
(playlist possibly partial), the trial stops immediately
and does NOT try the other mapping on top of a partial
state; the per-run snapshot is named in the log.

What trial-dedupe does NOT do, by design:
- It never calls the rotation probe, and it never changes
  the probe's duplicate refusal: sortprobe/selfprobe on a
  doubled playlist still refuse and change nothing.
- It never borrows another target's mapping, and it never
  flips on failure: a failed verify restores, then the
  other mapping is tried as a fresh, verified attempt,
  not as a silent correction of the first.
- A fresh mapping, when one exists, is used directly with
  no trial. A clean playlist applies nothing and needs no
  mapping at all.
- Menu dedupe (choice 3) and direct dedupe use this path;
  the daily run attempts trial-dedupe only when the daily
  playlist's probe refused on duplicate entries specifically
  (the probe output wording is checked, not just the exit
  code), and a failed trial-dedupe stops the daily run
  before shuffle/rediscover. Any other probe failure still
  stops the daily run immediately, with no dedupe attempt.

UNPROVEN ON A MAC: trial-dedupe on the real doubled
playlist, the mapping recorded by a successful trial, and
a subsequent shuffle after trial-dedupe. The sort-probe
AppleScript's own "other"
error text still says to set "the throwaway sort"; for a
self-probe that wording is stale (there is no throwaway),
and run.sh's failure log carries the corrected meaning.

## Failure mode 41: a restore under a wrong mapping cannot verify (2026-10-29, proven on the Mac)

On 2026-10-29 18:59 PT trial-dedupe (v3.0.4) on the real
main playlist tried forward first (1612 entries, 806
unique). The playlist's true mapping is reversed, so the
forward dedupe build verified-failed, as it should. Then
apply-order's internal restore rebuilt the pre-dedupe
snapshot with the SAME forward mapping, so it
verified-failed too and declared CRITICAL, and the
run.sh undo restore failed the same way. The pre-undo
snapshot file proved all 1612 entries were present at
undo start, in the exact reverse of the snapshot, and a
read-only diagnostic at 19:08 PT proved the current
list-read order is exactly the pre-dedupe snapshot order
(1612, first EC60833070C7D0B1, last 6471F2089E4E7F7D).
No songs were lost; the playlist was back at doubled
order and needed no restore. The trap is mechanical: a
restore under a wrong mapping cannot verify, by the same
mechanism as a build failure under that mapping, so a
single-mapping restore traps itself and wrongly declares
a playlist partial when every song is present, merely
reversed.

The fix (v3.0.5) is a RESTORE retry, not a build flip,
and the distinction must not be blurred later. A build
never retries its desired order under the opposite
mapping, and a failed build still exits non-zero and
records nothing. A restore's only job is to return to a
known snapshot, and each restore attempt is verified
against that snapshot before it counts, so every restore
now tries both mappings, given first then opposite:
apply-order's internal restore (failed build,
delete-empty failure, library shrink), undo's pre-undo
restore, and restore-original's snapshot put-back (the
same trap in the run.sh restore path). Only if neither
verifies does a script declare CRITICAL, with the
snapshot named. In run.sh, a trial-dedupe attempt whose
restore fails now means neither mapping restored, so the
trial stops critical with the snapshot named and does
not try the other trial mapping on top of a possibly
partial state; if the restore succeeds under either
mapping, the trial proceeds to the next mapping.

UNPROVEN ON A MAC: trial-dedupe completing on the real
doubled playlist under v3.0.5, the mapping recorded by
a successful trial, and a subsequent shuffle after
trial-dedupe.

## Failure mode 38: drop-in gaps closed, and the one left open (2026-10-29)

The stable-prep audit listed five gaps against v2.6 parity; the
drop-in package closes them, with the guards intact:

- Mapping validity is 48h, not 24h, in `run.sh`
  `mapping_for_build` and `daily.sh` `check_mapping`. An evening
  probe covers two mornings. Verify-after still fails closed if
  the sort changed in the window, so a stale mapping costs a
  refused run, never a corrupted playlist. No other guard moved.
- `./run.sh menu` re-invokes run.sh per choice, so menu builds
  keep every gate; the menu prints mapping status before a
  build and, since v3.0.3, auto self-probes on a missing
  or stale mapping instead of refusing outright, and never
  overrides a refusal.
- The "Last reshuffled" stamp runs only in apply-order, only
  after verification and the library-shrink check, only for
  shuffle/flow (run.sh stamp flag), and best-effort: an
  unsettable description logs skipped and never fails the
  apply. Undo/restore/dedupe/rediscover never stamp.
- Notifications are best-effort in run.sh and daily.sh and
  never fail a run.
- Shuffle size (100/250/500/1000/all) applies only to a
  whole-library shuffle into "SeTeR Shuffle"; a sized in-place
  shuffle refuses before any dump, because it would drop songs.
  Size-capped orders validate under "shuffle-size"
  (presence/multiplicity only).
- Dedupe logs every removed duplicate by artist and name.

Superseded 2026-10-29 by the Flow energy fix (see the changelog
flow-fix entry): Spencer authorized fixing flatness by any
offline means, and the fallback is now a vibe score using only
fields already in the dump (finer play tiers, group-8 genre
subgroups, finer skip bands, year era band, played-date
recency and date-added newness with a supplied clock), with an
arc-first walk (genre cost 0/3/8, year cost 0/2/4, +4 for
repeating the previous energy). The BPM-present path is still
byte-for-byte unchanged, and no tempo is invented. The fix is
proven only on a synthetic gospel-heavy library; the Mac Step
10d flowPreview run must show a rising arc before it is
claimed fixed against Spencer's real library.

## What the bridge is allowed to do

- Modify exactly one regular user playlist, resolved by name, and
  only after that playlist passes every check in
  `assertUserPlaylist`.
- Remove song entries from that playlist, and add songs to it by
  duplicating library tracks into it.
- Read the library (dump script only).

## What the bridge never does

- Never deletes a song from the library. Deleting a track from a
  user playlist removes that playlist entry only; the song stays in
  the library. No line in any bridge script deletes from
  `library playlist 1`. Verified by grep: the only `delete`
  statements that touch Music are
  `delete (every track of destPl whose media kind is song)` and
  `delete (every track of pl whose media kind is song)` in the
  apply and undo scripts, where `destPl`/`pl` have already passed
  `assertUserPlaylist`, and the equivalent inside each script's
  restore handler.
- Never creates a duplicate playlist entry from a bad order: orders
  are checked for duplicate IDs twice (Python before apply, bridge
  before writing), and an order that repeats an ID more times than
  the dump does refuses the run. The one exception is a
  one-playlist shuffle, whose dump itself repeats an ID for each
  duplicate playlist entry: there the order must match the dump's
  multiset exactly (same songs, same multiplicities), so duplicate
  entries are preserved as positions, never merged and never
  invented. Whole-library and Flow/Rediscover orders never repeat
  an ID, so a repeat there is still corruption.
- Never wipes a playlist to empty by accident: an empty order is
  refused outright. The only operation that produces an empty
  playlist is undo from a genuinely empty backup, which is a
  deliberate restore of an empty playlist.
- Never deletes non-song entries (videos, etc.) from a playlist:
  every delete is filtered to `whose media kind is song`, and
  verification only compares song IDs.
- Never duplicates into a non-empty playlist (mode 32's guard):
  every rebuild deletes, re-reads, and confirms 0 song entries,
  retrying the delete up to 5 times with a 5-second settle delay,
  and duplicates nothing if entries remain. A delete that is
  assumed but not verified is a known-unsafe step after the
  2026-10-29 doubling, and this guard does not depend on what
  made the delete lag: whatever the cause, a build that would
  have doubled the playlist now aborts instead, restoring only if
  the playlist was actually changed and reporting it unchanged if
  it was not.

## Failure-mode table

"Old behaviour" is the pre-hardening script (the exp-2026-10-28.2
bridge). "New guard" is what now stops it. "Mac test" is the check
that proves the guard on a real Mac.

| # | Failure mode | Old behaviour | New guard | How to test it on a Mac |
|---|---|---|---|---|
| 1 | Target resolves to the Library itself | The old script trusted the playlist name and never checked what it resolved to. | `assertUserPlaylist` requires class `user playlist`, not smart, and id different from `library playlist 1`; any check that cannot be performed fails closed (refuses). Checked in apply, undo, and every restore. | `./run.sh shuffle "Library"` (or any attempt to name the Library) must refuse before any change, exit non-zero, log the refusal. |
| 2 | Target is a smart playlist | Same trust-the-name problem; a smart playlist cannot be edited this way and the failure would be confusing. | Same `assertUserPlaylist` check (smart = refuse). | Point an apply at a smart playlist; it must refuse untouched. |
| 3 | Two playlists share a name | A bare `playlist "Name"` lookup silently picks one of them, so the wrong playlist could be rewritten. | `resolvePlaylist` counts matches: 0 = create (apply) or error (undo), >1 = refuse with the count, exactly 1 = use that object, never a fresh name lookup. | Create two throwaway playlists with the same name, run an apply naming it; it must refuse. Rename one, re-run; it must succeed on the right one. |
| 4 | Delete from playlist vs delete from library | Old code deleted from the named playlist, which was correct in practice, but nothing in the code proved it or guarded the Library case. | Guard in mode 1 plus the grep-verified delete audit above: every delete targets an asserted user playlist, never `library playlist 1`. | After any apply/undo, confirm in Music that the library song count is unchanged (apply must not change it; only playlist membership changes). |
| 5 | Empty order file | The old script would delete the playlist's songs and then add nothing back: a silent wipe. | Python `validate-order` refuses an empty order, and the bridge refuses it again before resolving anything. Emptying a playlist is only possible via undo of an empty backup. | Hand the apply script an empty order file (or a file with only newlines); it must refuse, playlist untouched, exit non-zero. |
| 6 | Duplicate persistent IDs in the order | The old script would duplicate the track into the playlist once per repeated ID, creating real duplicate entries. | Python validation refuses duplicates; the bridge re-checks with `sort \| uniq -d` before any change. | Order file with one ID twice; both `validate-order` and the bridge must refuse, playlist untouched. |
| 7 | Order ID not in the library dump | The old script silently skipped missing tracks (`on error` with no record), so everything after the gap shifted. | Python validation refuses with the missing IDs listed; the bridge collects lookup failures during the build instead of skipping, restores from backup, and reports the missing IDs. | Order with a bogus ID; run must refuse (Python) or restore (bridge, if the Python check is bypassed) and name the bogus ID. |
| 8 | Order count does not match the expected playlist size for a shuffle | The old script had no expected-size concept; a short order would silently drop songs. | Python validation: shuffle orders must be exactly the dump's song set (same count, same IDs). Bridge: verify-after compares the full ID list, not a count. | Shuffle order missing one song; `validate-order --mode shuffle` must refuse. |
| 9 | Truncated order file | A text file cut short still "verifies" against itself, so a count check would pass on a partial playlist. | Python validation requires the order JSON's `ids` list to equal the text file exactly (same IDs, same order, same count) and its `count` to agree. run.sh always passes both files. | Truncate the text order to fewer lines than the JSON; `validate-order` must refuse. |
| 10 | Malformed or non-UTF-8 order file | Old script would error partway or misread IDs. | Python: file must be valid UTF-8, no blank middle lines, no whitespace in IDs. Bridge: same strict read before any change. | Feed a non-UTF-8 order file and one with a blank middle line; both must refuse. |
| 11 | Backup not written and verified before any change | Old script wrote the backup with a plain write and never re-read it, so a failed write could be discovered only after the playlist was already changed. | Backup is written to `<backup>.tmp`, atomically renamed into place with `mv -f`, then re-read and compared exactly to the snapshot. Any failure aborts with the playlist untouched. The old backup is never truncated in place. | Make the backup path unwritable (or the state dir read-only) and run an apply; it must abort untouched. |
| 12 | Truncated, corrupt, or unwritable backup | Old undo deleted the playlist first and only then discovered a bad backup. | Apply: backup verified before any delete (mode 11). Undo: backup validated before anything is deleted; missing or corrupt backup aborts untouched. | Undo with a missing backup file and with a backup containing a blank middle line; both must refuse, playlist untouched. |
| 13 | First-run playlist is genuinely empty | An empty backup could be mistaken for corruption and refuse a legitimate first run. | Empty backup is explicitly valid: it snapshots an empty playlist, and undo of it restores an empty playlist. Documented here and in the code, not treated as corruption. | Apply to a brand-new empty throwaway playlist, then undo; the playlist must end up empty, not error. |
| 14 | Mid-apply failure (build error, Music quits) | Old script had no restore path: a failure partway left a half-built playlist and exited without saying what happened. | Any error after changes start triggers a restore attempt from the verified backup, and the script still exits non-zero. run.sh also attempts a restore via undo if the apply step fails. Partial restores are reported as CRITICAL with the backup path named. | On a throwaway playlist, force-quit Music mid-apply (large playlist gives a window); on relaunch, check the playlist and re-run undo from the backup in the state dir; it must come back exactly. |
| 15 | Verify-after is only a count check | A count check passes when songs are swapped, duplicated, or reordered. | Verify-after is an exact list comparison: same IDs, same order, no extras, no duplicates. Verification itself is wrapped so that Music quitting during verify also triggers a restore (mode 14). | After a successful apply, confirm in Music that the order matches the printed order exactly, not just the count. |
| 16 | Library shrinks or changes between dump and apply | The old script had a library-size check, but its behaviour was not documented and nothing acted on a mid-run shrink. | Kept and documented: run.sh passes the dump's song count as the apply script's 4th argument; if the library now holds fewer tracks, the run aborts untouched. The same check runs again after the build; a shrink during the run restores from backup. | Delete a song from the library between dump and apply (test library only); the apply must abort and restore. |
| 17 | Undo with a missing or corrupt backup | Old undo deleted the playlist's songs, then failed reading the backup, leaving the playlist empty. | Undo validates the backup first (exists, readable, no blank middle lines, no whitespace IDs) and snapshots the current playlist to `<backup>.pre-undo` (atomically written and verified) before deleting anything. A failed undo restores from the pre-undo snapshot. | Undo with no backup file; playlist must be untouched. Undo with a corrupt backup; same. |
| 18 | Undo restores only partially | Old undo reported success even if some backup songs could not be found. | Undo collects lookup failures, verifies exactly after rebuilding, and on any failure restores the pre-undo snapshot and exits non-zero, naming both backup paths on a CRITICAL failure. | Undo from a backup containing a bogus ID (edit a copy of a real backup); it must fail loudly and leave the pre-undo playlist intact. |
| 19 | Undo of an empty backup | Old undo's behaviour on an empty backup was untested. | Empty backup is valid (mode 13): undo deletes the playlist's songs and verifies an empty result. | Undo a throwaway playlist from its first-run (empty) backup; it must end empty with a success message. |
| 20 | Stale backup mistaken for a fresh one | The old runner reused one backup path per playlist, so a failed apply could "restore" from an older backup and revert the playlist to a much older state. | run.sh preserves any previous backup as `<backup>.prev` and clears the backup path before an apply, so the presence of the backup file after the apply step proves this run wrote it. On apply failure with no fresh backup, the log says the playlist was not changed, instead of restoring from a stale file. | Run an apply, let it fail before the backup step (e.g. bad order), and confirm the log says "no fresh backup was written" and the playlist is unchanged. |
| 21 | Two playlist names collide after sanitizing | Old backup names replaced spaces and slashes with underscores, so "My Playlist" and "My_Playlist" shared one backup file. | Backup filenames now include a short hash of the full playlist name, so distinct names cannot collide. Old backup files under old names still exist and can be used by calling undo.applescript directly with that file and a recorded sort-mapping argument (required now). | Create "A B" and "A_B" throwaway playlists, back up both, confirm two distinct backup files exist in the state dir. |
| 22 | Dump is partial or misaligned | The old dump's bulk-read helper padded every list to full length, so its "count is not n" check could never fire, and the `favorited` to `loved` fallback could never run. A mid-read library change could have put values on the wrong tracks. | Required lists (names, artists, albums, genres, played counts, played dates, added dates) must all have exactly n entries or the dump aborts unwritten. The bulk helper now returns a missing value on any failure or wrong count, so the fallback actually runs. | Hard to trigger deliberately; the guard is proven by code review and by the audit command reporting sane counts on a real library. |
| 23 | Failed dump leaves a stale dump for the next step | A dump written to a fixed path could be reused by a later step after a failed run. | run.sh writes each dump to a fresh temporary directory per run, and previews/applies read only that run's dump. | Run a failing dump (e.g. rename the bridge temporarily), then confirm no stale dump exists at a reusable path. |
| 24 | History recorded after a failed apply | Would burn a song's Rediscover cooldown even though the playlist never changed. | `record-history` runs only after a successful apply (unchanged behaviour, now wired through the step helper so a failed apply cannot fall through to it). | Run a failing rediscover; confirm the history file is byte-identical afterwards. |
| 25 | Python path with spaces silently mis-parsed | run.sh splits check-python's "path (version)" output on the first space; a spaced path would point at the wrong interpreter. | check-python.sh refuses loudly if the interpreter path contains a space, telling the user to set SETER_PYTHON. | Not Mac-testable without a spaced install; guard is proven by reading check-python.sh. |
| 26 | Bridge errors missing from the log | The old runner piped only stdout to the log, so AppleScript errors could vanish. | Every step runs through run.sh's `step()` helper, which sends both stdout and stderr to the log and writes a GATE OK / GATE FAILED line, so the log proves which gate fired. | Trigger any failure and confirm the error text and the GATE FAILED line are both in `~/Library/Logs/seter-shuffle-python/run.log`. |
| 27 | Restore's own verify throws instead of reporting failure | A restore that could not verify would throw a raw Music error, hiding whether a restore was attempted. | `tryRestore` never throws from its verify step: a verify error returns `{ok:false}`, and the caller reports it as a failed restore with the backup path. | Covered by mode 14's test; the message must name the backup file, not a raw Music error. |
| 28 | Trimming an empty string reads a character that does not exist | AppleScript does not guarantee short-circuit evaluation, so a condition like "count > 0 and character 1 is a space" could read character 1 of an empty string. | `trimText` in both scripts is written as plain loops guarded by `t is not ""`, so no character of an empty string is ever read. | Covered by modes 5, 10, and 12 (empty and malformed files exercise trimText). |
| 29 | Delete lags at large-playlist scale, doubling the playlist (delete-empty guard) | A rebuild assumed its delete took effect and duplicated a full copy on top of entries the delete had not removed; the real playlist doubled from 806 to 1612 entries (each song exactly twice) between the 00:21 diagnostic and the 00:41 run on 2026-10-29. Mechanism unproven, but the guard does not depend on it. | `deletePlaylistSongs` in apply, undo, restore-original, and sort-probe: delete, re-read, confirm 0 song entries, retry up to 5 times with a 5-second settle delay; on failure return `delete-not-empty` and duplicate nothing; callers restore only if the playlist changed, else report it unchanged. | Doubled throwaway test (Stage 2 step 9): a throwaway with each song twice must dedupe cleanly, and a throwaway whose delete is forced to fail (if a failure can be induced) must abort with the playlist unchanged, never doubled. The delete-lag mechanism itself is still unproven on a Mac: if no throwaway reproduces it, the guard stands as prevention, not as a proven root cause. |
| 30 | run.sh captured a log line into the mapping (narrative mode 31) | `mapping_for_build` logged with `log()` (tee to stdout) while callers captured it with `$(...)`, so every captured mapping carried a log line and the bridge refused it: no .1 build through run.sh could run at all. | `mapping_for_build` logs with `logfile()` only; a structural test extracts the function body and refuses any `log ` call in it. | Run any build through run.sh (not direct osascript) on a throwaway: the apply must reach Music instead of failing at the mapping argument. If it fails there, the capture bug is back. |
| 31 | Failed run overwrote the only good backup (narrative mode 32) | The 00:41 run wrote a doubled-state snapshot to the main backup path; only `.prev` saved the original, and one more failed run would have overwritten `.prev` too. | Per-run snapshot files, installed as the main backup only after a verified successful apply; previous main backup kept as `.prev`; newest 10 per-run snapshots kept as a chain; failure restores use the per-run snapshot and leave the main backup untouched. | Run a failing apply on a throwaway (e.g. a bad order that passes Python validation but fails in the bridge, or a forced failure), then confirm the main backup file is byte-identical to before the run and a per-run snapshot exists. |
| 32 | Stale mapping survived a failed re-probe; restore had no gated path; undo could discover a missing backup after deleting (narrative mode 33) | A failed sort-probe left the old mapping in place; restore-original could only be called directly (no freshness check); undo resolved the playlist before checking the backup file existed (the script itself validates first, so this was a clarity gap, not a data-loss path). | Sort-probe failure deletes the recorded mapping; `./run.sh restore` gates backup existence and mapping freshness like undo; `run.sh undo` refuses with a list of recent backups when the main backup file is missing. | Fail a sort-probe (e.g. on a title-sorted throwaway returning "other"), then attempt a build: it must refuse for lack of a mapping, not proceed under the old one. Run `./run.sh restore` on a throwaway with a missing backup file: it must refuse untouched. |
| 33 | Flow into a missing playlist fails at the first bulk read, -1728 (narrative mode 34) | `resolvePlaylist(allowCreate=true)` created "SeTeR Flow" via `make new user playlist`, and the next bulk filtered ID read on the fresh empty playlist failed with -1728 before any snapshot existed; safety held (nothing changed), but a flow into a missing playlist could never succeed. | Apply-order re-resolves a created playlist by id with a fresh lookup and builds only from that reference; `playlistIDs` falls back on a bulk-read error to an unfiltered count (0 returns {}, anything else rethrows); `deletePlaylistSongs` applies the same fallback to its empty re-read. | Delete "SeTeR Flow" in Music if it exists, then run `./run.sh flow` (under a fresh sortprobe mapping): it must create the playlist and apply exactly with APPLY OK. Then run flow again on the now-existing playlist: it must refresh it exactly. A -1728 at the snapshot step on either run is a fail. |
| 34 | Mapping measured on one sort used for a playlist with a different sort (narrative mode 35) | The .4 Flow runs used the main playlist's reversed mapping (Playlist Order descending) for the new, default-sorted SeTeR Flow playlist; a reversed build on a forward-sorted playlist lands backwards, so verify correctly refused. Under .4 one shared mapping file let any build silently reuse any other build's mapping. | Mappings are per-target files (name plus hash); a build reads only its own target's file, validates its TARGET field, requires a SORT field and a fresh (<48h) timestamp; the pre-.5 shared sort-mapping.txt is ignored; sortprobe requires throwaway, target, and sort label; GATE lines print the recorded throwaway and sort label before building. | Attempt `./run.sh flow` with only a main-playlist mapping present: it must refuse for lack of a SeTeR Flow mapping. Then run `./run.sh sortprobe` on a throwaway set to SeTeR Flow's sort for target "SeTeR Flow", and run flow: it must apply exactly with APPLY OK. |
| 35 | Undo fails with -1728 on an empty playlist and is reported as "may be partial" (narrative mode 36) | The .4 empty fallback went into apply-order and the retired probe script but not into undo or restore-original; undo's first bulk playlistIDs read fails with -1728 on the empty SeTeR Flow playlist, so undo died before changing anything, and run.sh reported "may be partial" when nothing had changed. | Undo, restore-original, and sort-probe carry the same playlistIDs and delete empty fallbacks as apply-order; pre-change snapshot failures in undo/restore rethrow with a PLAYLIST_UNTOUCHED marker; run.sh's post-apply restore branch logs "untouched, NOT partial" for that marker and keeps "may be partial" for all other restore failures. | Run undo (or restore) on a fresh empty throwaway: it must not fail with -1728, and a failed restore that died at the snapshot read must be logged as untouched, not partial. |
| 38 | Drop-in gaps vs v2.6 (narrative mode 38) | Stable-prep had no menu, no description stamp, no notifications, CLI-only size, counts-only dedupe, and a 24h mapping window that made a daily run need a probe every day. | 48h mappings (evening probe covers two mornings, verify-after still fails closed); Terminal menu that re-invokes run.sh per choice; best-effort "Last reshuffled" stamp only after verified shuffle/flow; best-effort notifications; size only for whole-library shuffles (sized in-place refuses, "shuffle-size" validation); dedupe names every removed duplicate. Flow energy deliberately unchanged. | Menu: run `./run.sh menu`, shuffle a throwaway, confirm the mapping-status line appears and the build applies. Stamp: after a throwaway shuffle, check the playlist description in Music reads "Last reshuffled: ..."; if Music has no settable description, the log must say the stamp was skipped and the apply still succeeded. Size: `./run.sh shuffle 100` must fill "SeTeR Shuffle" with 100 songs; `./run.sh shuffle <throwaway> 100` must refuse. Dedupe: dedupe a doubled throwaway and confirm the log names each removed duplicate. 48h: a mapping 47h old must pass, 49h old must refuse. |

## Further audit (2026-10-28): other potential bugs, beyond the reversal

Every bridge script, run.sh, check-python.sh, and the Python modules
that feed the bridge were re-read line by line after the reversal.
For each candidate: the trigger, whether it can actually bite on a
real Mac, and the fix or the reason no fix is needed. Severity is
about a real playlist, not about code tidiness.

| # | Candidate bug | Trigger | Can it bite? | Fix / status |
|---|---|---|---|---|
| A1 | Playlist UI sort setting changes the order AppleScript sees after a build | User sorts a playlist by a column in Music, then shuffles it | CONFIRMED as the leading model for the 2026-10-28 failure (mode 30): the real playlist is sorted by Playlist Order descending, and its list read is the exact reverse of its original backup. A title/artist sort would not produce that exact reverse, so the sort here is playlist-order descending specifically. | Fixed procedurally, not by reading the sort (Music exposes no playlist sort property to AppleScript): a throwaway carrying the target's sort is measured by sort-probe, and builds run only under that recorded mapping; any other sort returns "other" and aborts. Stage 0 also requires checking whether a sorted playlist re-sorts after a build (see mode 30's falsifiers). |
| A2 | iCloud Music Library sync reorders, restores, or conflicts with a build in progress | Playlist syncs while a 2-minute delete/re-add loop runs | Theoretical; sync does not reorder a playlist on its own, but a remote edit landing mid-build could change the playlist between snapshot and verify, which would then (correctly) fail verification and restore | No code fix; the backup-and-restore design already covers it (verify fails, restore runs). Procedural: do not edit the playlist on another device during a build, and pause sync-sensitive edits until the run finishes. |
| A3 | Currently-playing track deleted from its playlist mid-run | The playlist being shuffled is the one now playing | Minor, real: deleting the playing track's playlist entry does not remove it from the library, so playback itself survives, but the up-next queue may rebuild or skip | No abort added: shuffling the playlist you are listening to is a normal use case, and aborting on it would break the daily shuffle. Procedural: pause playback before a build if the queue matters; noted in Stage 0. |
| A4 | Cloud-only / unavailable / not-downloaded tracks fail to duplicate | A playlist entry whose library track is missing, removed from the catalog, or undownloaded | Handled already: the build collects lookup failures instead of skipping silently, then restores from backup and names the missing IDs. It cannot bite as data loss, only as a refused run | No fix needed; covered by modes 7 and 18. |
| A5 | Persistent ID changes (song deleted and re-added to the library) | A track leaves the library between dump and apply | Handled already: Python validation refuses IDs not in the dump, the bridge collects missing IDs and restores, and the mid-run library-size check catches a shrink during the run | No fix needed, with one correction (see A9): the pre-run library-size check now only runs for whole-library dumps. |
| A6 | Non-song entries (videos, etc.) mixed into a playlist | Playlist holds a video alongside songs | Handled already: every delete and every verify filters to `media kind is song`, and non-song entries are left in place. One caveat: the positional cross-check in the probe and in the old flip logic is unreliable when non-song entries exist, because track positions then include them; the probe requires exactly 3 song tracks in its own playlist, so this cannot affect a probe verdict | No fix needed for builds; probe is immune by construction. |
| A7 | Large playlists and AppleScript timeouts | Playlist of ~1000+ songs; the .4 build took ~2 minutes for 806 songs | Plausible for larger playlists: a single tell block with hundreds of duplicate events could approach AppleScript's default timeout, which would surface as a build error and trigger a restore (safe, but a failed run) | Fixed: build and restore loops in apply, undo, and restore-original now run inside `with timeout of 3600 seconds` blocks. This is precaution, not a claimed root cause: the .4 failure reported verification failure, not a timeout. |
| A8 | Duplicate playlist name created between resolve and build | A second playlist with the target name appears mid-run | Cannot bite: resolve returns an object reference, and every later step uses that object, never a fresh name lookup, so a new same-named playlist cannot redirect the build | No fix needed; checked by reading resolvePlaylist and every use site. |
| A9 | run.sh passed the wrong count as the apply script's library-size check for one-playlist shuffles | `./run.sh shuffle "Some Playlist"`: the dump is a playlist dump (806 songs), but the .4 runner passed its count as the "expected library song count", comparing library size (~940) against a playlist count | Weak guard, not data loss: the comparison only failed on a catastrophic library shrink below the playlist size, so a smaller shrink slipped past the pre-check. The mid-run check (library size before vs after the build) and the missing-ID path still covered the actual danger | Fixed: run.sh now passes the library count only for whole-library dumps and omits it for one-playlist shuffles; the apply script's argument order changed accordingly (mode, then duplicate flag, then optional library count). |
| A10 | Backup filename with quotes, slashes, unicode, or newlines | Playlist name contains such characters | Mostly handled already: the hash prevents collisions, shell paths are quoted, and AppleScript paths travel as arguments (not shell text) and through `quoted form` in do-shell-script calls. One hole: a newline in a playlist name put a newline in the backup filename and broke log lines naming it | Fixed in run.sh: newlines and carriage returns are neutralized in backup_path_for before sanitizing. Quotes and unicode need no change. |
| A11 | Stale dump reuse across runs | A failed dump leaves a file the next step mistakes for a new one | Cannot bite: run.sh works in a fresh mktemp directory per run, the dump script writes atomically (temp file + rename + non-empty check), and a failed dump step exits before the core ever reads it. A SIGKILLed run can leave its temp dir behind, but no later run reuses that directory | No fix needed; covered by mode 23. |
| A12 | Order JSON vs text cross-check gaps | Core writes order JSON but the text file is truncated or stale | Cannot bite via run.sh: validate-order requires the JSON ids list to equal the text file exactly and the JSON count to agree; a truncated text file fails before Music is touched. Direct CLI use without --order-json skips the cross-check, but run.sh always passes both files | No fix needed. |
| A13 | Dump order vs playlist order for shuffle/Flow/Rediscover | The dump's order is the list-read order, which under read-reversed is the reverse of the display order | Shuffle: no effect (a shuffle is a permutation of the set; the printed order is the display target, and the mode formulas make the display match it). Flow/Rediscover: no effect (their orders are generated from library tracks, not from playlist order; the pool draw is the only place dump order matters, and there it only affects which songs a capped random pool holds, which is inherent randomness, not correctness) | No fix needed; the mode formulas in order_direction.py are what make the printed order equal the display order in all modes. |
| A14 | .4 duplicate refusal blocked legitimate playlist shuffles | Throwaway or real playlist holding the same song twice (Stage 1 of the old procedure deliberately used one) | Real, and it would have bitten Stage 1 itself: the dump of such a playlist repeats the ID, load_library refused duplicate IDs, and the bridge refused duplicate order IDs, so shuffling it failed closed before any build | Fixed in three places, all multiplicity-based: load_library gains allow_duplicates (passed only for one-playlist shuffles via a new --allow-duplicates CLI flag that run.sh passes only in that case); validate-order's shuffle check is now multiset equality and its duplicate rule is "no more copies than the dump"; apply-order takes a duplicate allowance flag from run.sh, set only when the dump itself repeats an ID. Whole-library orders still refuse any repeat. |
| A15 | .4 trimText, spaced-python-path guard, hashed backup names, verify-during-verify wrapping | Re-check of the .4 hardening for holes | All four hold on re-read. trimText never reads a character of an empty string (loops guarded by `t is not ""`). check-python.sh refuses spaced interpreter paths, and run.sh's first-space split is safe exactly because of that refusal. Hashed backup names prevent sanitization collisions (the only residual case, neither shasum nor md5 existing, cannot happen on macOS, which ships both). Verify errors in apply and tryRestore are wrapped and trigger restores, never unhandled exits | No fix needed. |
| A16 | Dump JSON escaping of exotic control characters | Track name contains a control character other than backslash, quote, newline, carriage return, or tab | Real but rare: the old escaper left such characters raw, making the JSON unparseable, which stopped the run fail-closed (safe, but the library could not be used at all until the track was renamed) | Fixed: jsonEscape in dump-library.applescript is now a character loop that escapes every control character as \u00XX; non-ASCII passes through as UTF-8. Like all bridge changes here, this is untested on a Mac until the procedure runs. |
| A17 | CLI shuffle --size produces an order validate-order then refuses | Direct CLI use: `shuffle --size N` truncates the shuffled list, but validate-order's shuffle rule requires the full dump set | Fail-closed confusion only: run.sh never passes --size for shuffle, so no run.sh flow hits it; a direct CLI user gets a refusal with no explanation that --size was the cause | No code change (refusing is the safe behaviour); noted here so the refusal is understood. Do not "fix" it by loosening the shuffle rule. |
| A18 | Python validate-backup accepts a file of only newlines; the bridge undo refuses it | Backup file containing only blank lines | No operational impact: run.sh never calls validate-backup in the apply/undo flow (undo validates the backup itself, fail-closed), and a bridge-written backup is never only newlines (an empty backup is a zero-byte file). The inconsistency is documented, not papered over | No fix; the bridge's refusal is the safer side, and changing the .4 test that codified "only newlines counts as empty" would churn a settled rule for no operational gain. |
| A19 | The 2026-10-28 one-off fix script's flip logic (restore-original as first written) | Running it on a playlist that is already correct on screen, under read-reversed | Real and dangerous: it reads backwards, decides a flip is needed, rebuilds in reverse order, and declares success on a playlist it just broke (worked through in mode 29 above) | Fixed 2026-10-29: rewritten mapping-only (a recorded sort-matched mapping is required; no probe path, no flip path). Never run the 2026-10-28 version of that script again, on any playlist. |
| A20 | run.sh probe output parsing | Probe verdict line malformed, duplicated, or missing | Cannot silently pass: probe_mode requires exactly one PROBE_VERDICT line naming one of the three modes AND a PROBE_CLEANUP_OK line, or the gate fails. NOTE 2026-10-29: this now gates only the standalone `./run.sh probe` command; builds use the sort-mapping gate instead (mode 30). The parsing pipeline itself is covered by a Python test against a sample probe block | No fix needed; tested. |

## The uncovered case, stated without softening

If the machine loses power, or Music is force-quit, in the middle
of the delete/re-add loop, no script can run its restore, because
the script itself is gone. What survives is the verified backup
file: it was written and renamed into place before any change, and
it lives in the state directory
(`~/Library/Logs/seter-shuffle-python/`), not in a temporary
directory that a reboot might clean. Recovery is:

1. Reopen Music.
2. Re-run undo for that playlist:
   `./run.sh undo "<playlist name>"`
   (or call undo.applescript directly with the backup file and a
   recorded sort-mapping argument, if the backup predates the
   hashed filenames, mode 21; the mapping argument is required
   now).
3. Check that the playlist's songs and order match what they were
   before the interrupted run. If undo also reports a failure, the
   backup file named in the error is the file to keep: do not delete
   it, and do not re-run an apply until the playlist has been
   restored from it.

There is no way to make this case fully automatic in AppleScript:
the restore can only run if something is alive to run it. The
backup-first design is the mitigation, and the state directory is
where the mitigation lives.

## Mac verification procedure

Do this in order. Use a throwaway playlist first, then a real one,
then undo, checking counts and exact order at each step. Do not
skip the throwaway stage: the negative tests below deliberately
feed the bridge bad input, and a bug in a negative path must not
cost a real playlist. NOTHING in this procedure runs on "My New
Sandwich Recipe" or any other real playlist until Stage 3, and Stage
3 says explicitly to pick a playlist you can afford to have
rewritten, not the daily playlist on its first run.

### Stage 0: diagnostic, then sort-matched probe (do this first, before any build)

Nothing in this stage modifies a real playlist. The diagnostic is
read-only; the sort-probe touches only its own throwaway.

1. Read-only diagnostic on the target, if it is a real playlist you
   may one day restore: `osascript bridge/diagnose-playlist.applescript
   "<playlist name>"`. Record COUNT_SONGS, LIST_FIRST, LIST_LAST,
   POS_FIRST, POS_LAST, INDEX_OF_LIST_FIRST. Compare LIST_FIRST /
   LIST_LAST against the backup file's first/last lines: first ==
   backup first and last == backup last means the current list
   state is the backup order; first == backup last and last ==
   backup first means the exact reverse; neither means shuffled or
   partial, so stop and report the lines verbatim. Do NOT infer
   manual order from INDEX_OF_LIST_FIRST (see mode 30): it is a
   reported value only. For full exactness (the diagnostic prints
   ends only), run the read-only dump
   `osascript bridge/dump-library.applescript /tmp/<name>-now.json
   "<playlist name>"` and compare its full ID list against the
   backup and against reverse(backup).
2. UI sort check on the target, in Music itself: which column (if
   any) shows a sort arrow, and which direction? Report the column
   and direction exactly, or "no sort arrow, manual order". Also
   note whether playback is coming from the playlist and whether a
   track in it is selected. This is the sort the throwaway in step
   3 must carry.
3. Sort-matched throwaway probe (the gate for every build):
   create a throwaway playlist with at least 5 distinct songs, set
   its sort in Music to EXACTLY the target's sort from step 2
   (Playlist Order descending for the 2026-10-28 failure), and run
   `./run.sh sortprobe "<throwaway name>" "<target>" "<sort-label>"`.
   It must print `MAPPING: forward` or `MAPPING: reversed` plus
   SORTPROBE_OK, record the mapping FOR THAT TARGET ONLY
   (valid 48 hours), and restore the throwaway to its snapshot.
   An "other" mapping, a failed restore, or a missing mapping
   file means STOP: no build will run, by design. If the
   throwaway's sort is not the target's sort, the mapping is
   the wrong mapping; set the sort correctly and re-probe.
   A mapping measured on one playlist's sort NEVER transfers
   to a playlist with a different sort (mode 35): Flow needs
   its own sortprobe on a throwaway set to SeTeR Flow's sort,
   even when a main-playlist mapping already exists.
   The old `./run.sh probe` (fresh playlist) is a standalone
   sanity check only and is NOT a substitute for this step: it
   measures a playlist that does not share the target's sort, and
   no build reads its verdict.
4. Throwaway sort controls (all throwaway-only, before any build
   that matters):
   a. A throwaway sorted by Playlist Order DESCENDING must
      reproduce the original failure mode on the OLD code path
      (or at least fail verification) and then PASS with the new
      sort-aware code (shuffle, then undo, exact order both ways).
      If a descending-sorted throwaway passes on the old code,
      the sort theory is dead: stop and report that.
   b. A throwaway on manual / Playlist Order ascending sort must
      pass with the new code (shuffle, then undo, exact order).
   c. A throwaway sorted by Title (or any other column) must
      ABORT untouched: sort-probe must return "other" and no build
      may run on it. If a build proceeds on a title-sorted
      throwaway, the abort path is broken: stop.
   d. Keep playback paused before each build, and leave throwaways
      on the sort being tested (do not re-sort mid-test).

### Stage 1: throwaway playlist, happy path

### Stage 1: throwaway playlist, happy path

1. Create a throwaway playlist in Music with at least 10 songs,
   including one song twice (a real duplicate entry) so the backup
   and restore paths are exercised with duplicates present.
2. Note the exact song order (screenshot or write it down).
3. Run `./run.sh audit` and confirm it changes nothing.
4. Run `./run.sh flowPreview` and confirm it changes nothing.
5. Run `./run.sh flow` and confirm "SeTeR Flow" appears with the
   printed order, and that the throwaway playlist is untouched.
6. Run `./run.sh shuffle "<throwaway name>"` and confirm the
   playlist now holds exactly the same songs in the printed order
   (same count, same songs, new order, both copies of the duplicate
   entry present and reordered as positions, not merged), and that
   the library song count is unchanged. The run's log must show
   the recorded sort mapping from Stage 0 step 3, and the
   throwaway's sort must be the sort that mapping was measured
   under; a build under any other mapping, or with no mapping
   file, must refuse before touching the playlist.
7. Run `./run.sh undo "<throwaway name>"` and confirm the playlist
   is back to the exact order noted in step 2, including the
   duplicate entry in its original position.

### Stage 2: throwaway playlist, negative paths

Run each of these against the throwaway playlist and confirm the
playlist is byte-for-byte unchanged afterwards (same songs, same
order) and the run exits non-zero with a message naming the problem:

1. Ambiguous name: duplicate the throwaway playlist's name, then
   apply. Must refuse (mode 3). Delete the duplicate afterwards.
2. Empty order: feed the apply script an empty order file directly.
   Must refuse (mode 5).
3. Duplicate order: a whole-library or Flow order file with one ID
   twice, beyond what its dump holds. Must refuse (mode 6 as
   revised: multiplicity, not a blanket refusal; a one-playlist
   shuffle order that repeats an ID exactly as often as its dump
   does is legitimate and must NOT refuse, per Stage 1 step 6).
4. Missing-ID order: order file with one bogus ID. Must refuse or
   restore, and name the bogus ID (mode 7).
5. Truncated order: text order shorter than its JSON. Must refuse
   via `validate-order` (mode 9).
6. Undo with a missing backup: rename the backup away, run undo.
   Must refuse untouched (mode 17). Restore the backup afterwards.
7. Undo of an empty backup: apply to a brand-new empty playlist,
   then undo. Must end empty with success (modes 13, 19).
8. Backup collision: create "A B" and "A_B" playlists, run an apply
   on each, confirm two distinct backup files (mode 21).
9. Dedupe on a doubled throwaway (the 2026-10-29 recovery path):
   make a throwaway with each song twice (duplicate every entry in
   Music), run `./run.sh dedupe "<throwaway>"`, and confirm it ends
   with each song exactly once, in first-occurrence order, and that
   the run log names the per-run snapshot. Then run dedupe again
   on the now-clean throwaway: it must report no duplicates and
   apply nothing (no rebuild of a clean playlist).
10. Failing apply must not touch the main backup: note the main
    backup file's bytes, force an apply failure on a throwaway
    (for example, an order file edited to fail in the bridge after
    Python validation), and confirm the main backup file is
    byte-identical afterwards, a per-run snapshot file exists, and
    the log says the main backup was not overwritten.
11. Failed sort-probe deletes the mapping: run sortprobe on a
    title-sorted throwaway (must return "other"), then attempt a
    build: it must refuse for lack of a recorded mapping, not
    proceed under any previous mapping.

### Stage 3: real playlist, then undo (explicit approval required)

1. Pick a real playlist you can afford to have rewritten (not the
   daily playlist on its first run). Do NOT run this stage on "My
   New Sandwich Recipe" until: (a) Stage 0 steps 1-4 have all
   passed, including a descending-sorted throwaway passing with
   the new code and a title-sorted throwaway aborting; (b) the
   real playlist's current list-read state has been measured by
   Stage 0 step 1 and the backup it will be restored from has
   been verified against that measurement; and (c) the user has
   explicitly approved this run after seeing (a) and (b), knowing
   the two prior real-playlist runs both failed in the same loop.
2. Note its exact order (and its UI sort, which must match the
   sort the recorded mapping was measured under; if it does not,
   re-probe first and do not proceed on a stale mapping).
3. Run the shuffle or flow apply, confirm the new order matches
   the printed order exactly, and confirm the library song count
   is unchanged.
4. Run undo and confirm the original order is restored exactly.
5. Eyeball the display: after the restore, the first and last
   songs shown in Music must match the backup order's first and
   last songs (by name, via a read-only dump if needed). The
   bridge verifies the LIST read, not the display; if the display
   disagrees with the list read after a verified restore, report
   that as a finding, do not paper over it.
6. Read `~/Library/Logs/seter-shuffle-python/run.log` and confirm
   every step shows GATE OK, or that any GATE FAILED line names
   the gate that fired (mode 26), and that the log names the
   recorded sort mapping used.

### Stage 4: the uncovered case (throwaway playlist only)

1. Start an apply on a large throwaway playlist (hundreds of
   songs, so the loop takes visible time).
2. Force-quit Music mid-run.
3. Reopen Music, check the playlist state (it may be partial;
   that is expected here), then re-run undo from the backup file
   in the state dir.
4. Confirm the playlist is restored exactly. If it is not, keep
   the backup file and report the failure: that is the one case
   this design cannot cover automatically, and it must be reported
   as such, not papered over.

## Known verification caveats

- The `assertUserPlaylist` id check compares the target's id to
  `library playlist 1`'s id. If the Music version on the test Mac
  does not expose `id` on the library playlist, every apply and
  undo will refuse (fail-closed, loud, playlist untouched). That
  would be a false refusal, not a data loss, and the fix would be
  to drop the id comparison (the class and smart checks already
  exclude the Library in practice). If stage 1 refuses everything,
  check this first.
- The dump script's JSON escaper now escapes every control
  character (audit item A16), but that new character loop is itself
  untested on a Mac, like everything else here: if a dump comes out
  malformed, the Python core still refuses to load it fail-closed
  before any apply, and the escaper is the first place to look.
- The probe depends on the track `index` property being exposed on
  playlist tracks in this Music version. If it is not, the probe
  reports ambiguous and every apply/undo refuses (fail-closed, loud,
  playlist untouched). That would be a false refusal, not a data
  loss; the fallback then is the manual eyeball step plus an
  explicit recorded sort-mapping passed to the scripts, never a
  guessed mode (mode 30).
- The probe's positional read travels through the same scripting
  bridge as the list read (mode 29's limits). If Stage 0's eyeball
  step disagrees with the probe verdict, believe the eyeball step,
  stop, and report both: the probe has misclassified, and no build
  should proceed on that verdict.
- Backup files from before the hashed naming (mode 21) are not
  found by the new `./run.sh undo`, because it computes the new
  name. They are still valid: call undo.applescript directly with
  the old file path AND a recorded sort-mapping argument (the
  mapping argument is required now; an old two-argument undo call
  fails loudly instead of building unmapped).
- Direct (non-run.sh) calls to apply-order, undo, and
  restore-original now REQUIRE a recorded sort-mapping argument.
  Old call shapes without a mapping fail loudly before anything
  changes. That breakage is intentional: an unmapped build is how
  the .4/.5 failures happened. But direct calls still bypass the
  24-hour freshness check (a script cannot know when its mapping
  argument was measured), so the supported path is run.sh only,
  including `./run.sh restore` for restore-original; a direct call
  is expert-only and must be given a mapping measured within 24
  hours on a throwaway carrying the target's sort.
- The newest backup file is not automatically the good one: since
  the per-run change, the main backup is installed only after a
  verified successful apply, and per-run snapshots (newest 10)
  plus `.prev` form the chain. Before restoring from any backup,
  check it against a known state (a dump comparison, or the
  backup's first/last lines against a known order); a snapshot
  taken from an already-corrupted playlist faithfully records the
  corruption, and restoring from it would restore the corruption.
