# Bridge safety: what cannot go wrong, and what still needs a Mac to prove

Status, stated plainly: **this document describes a reviewed design,
not a tested one.** The Python core and its validation were tested on
Linux (101 tests, all passing). The AppleScript bridge cannot run here:
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
refuse without a mapping fresher than 24 hours, and pass it to
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
   `./run.sh sortprobe "<throwaway name>"`. It must print
   `MAPPING: forward` or `MAPPING: reversed` plus SORTPROBE_OK,
   record the mapping (valid 24 hours), and restore the throwaway
   to its snapshot. An "other" mapping, a failed restore, or a
   missing mapping file means STOP: no build will run, by design.
   If the throwaway's sort is not the target's sort, the mapping
   is the wrong mapping; set the sort correctly and re-probe.
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
  the .4/.5 failures happened.
