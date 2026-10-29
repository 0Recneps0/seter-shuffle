# Bridge safety: what cannot go wrong, and what still needs a Mac to prove

Status, stated plainly: **this document describes a reviewed design,
not a tested one.** The Python core and its validation were tested on
Linux (67 tests, all passing). The AppleScript bridge cannot run here:
this machine has no Music app and no osascript, so no bridge script
has ever been executed. Nothing below claims a bridge script works.
The Mac verification procedure at the end is what turns "reviewed"
into "proven", and until it has been run, treat the bridge as
unproven.

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
  before writing), and a duplicate refuses the run.
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
| 21 | Two playlist names collide after sanitizing | Old backup names replaced spaces and slashes with underscores, so "My Playlist" and "My_Playlist" shared one backup file. | Backup filenames now include a short hash of the full playlist name, so distinct names cannot collide. Old backup files under old names still exist and can be used by calling undo.applescript directly with that file. | Create "A B" and "A_B" throwaway playlists, back up both, confirm two distinct backup files exist in the state dir. |
| 22 | Dump is partial or misaligned | The old dump's bulk-read helper padded every list to full length, so its "count is not n" check could never fire, and the `favorited` to `loved` fallback could never run. A mid-read library change could have put values on the wrong tracks. | Required lists (names, artists, albums, genres, played counts, played dates, added dates) must all have exactly n entries or the dump aborts unwritten. The bulk helper now returns a missing value on any failure or wrong count, so the fallback actually runs. | Hard to trigger deliberately; the guard is proven by code review and by the audit command reporting sane counts on a real library. |
| 23 | Failed dump leaves a stale dump for the next step | A dump written to a fixed path could be reused by a later step after a failed run. | run.sh writes each dump to a fresh temporary directory per run, and previews/applies read only that run's dump. | Run a failing dump (e.g. rename the bridge temporarily), then confirm no stale dump exists at a reusable path. |
| 24 | History recorded after a failed apply | Would burn a song's Rediscover cooldown even though the playlist never changed. | `record-history` runs only after a successful apply (unchanged behaviour, now wired through the step helper so a failed apply cannot fall through to it). | Run a failing rediscover; confirm the history file is byte-identical afterwards. |
| 25 | Python path with spaces silently mis-parsed | run.sh splits check-python's "path (version)" output on the first space; a spaced path would point at the wrong interpreter. | check-python.sh refuses loudly if the interpreter path contains a space, telling the user to set SETER_PYTHON. | Not Mac-testable without a spaced install; guard is proven by reading check-python.sh. |
| 26 | Bridge errors missing from the log | The old runner piped only stdout to the log, so AppleScript errors could vanish. | Every step runs through run.sh's `step()` helper, which sends both stdout and stderr to the log and writes a GATE OK / GATE FAILED line, so the log proves which gate fired. | Trigger any failure and confirm the error text and the GATE FAILED line are both in `~/Library/Logs/seter-shuffle-python/run.log`. |
| 27 | Restore's own verify throws instead of reporting failure | A restore that could not verify would throw a raw Music error, hiding whether a restore was attempted. | `tryRestore` never throws from its verify step: a verify error returns `{ok:false}`, and the caller reports it as a failed restore with the backup path. | Covered by mode 14's test; the message must name the backup file, not a raw Music error. |
| 28 | Trimming an empty string reads a character that does not exist | AppleScript does not guarantee short-circuit evaluation, so a condition like "count > 0 and character 1 is a space" could read character 1 of an empty string. | `trimText` in both scripts is written as plain loops guarded by `t is not ""`, so no character of an empty string is ever read. | Covered by modes 5, 10, and 12 (empty and malformed files exercise trimText). |

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
   (or call undo.applescript directly with the backup file if the
   backup predates the hashed filenames, mode 21).
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
cost a real playlist.

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
   (same count, same songs, new order), and that the library song
   count is unchanged.
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
3. Duplicate order: order file with one ID twice. Must refuse
   (mode 6).
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

### Stage 3: real playlist, then undo

1. Pick a real playlist you can afford to have rewritten (not the
   daily playlist on its first run).
2. Note its exact order.
3. Run the shuffle or flow apply, confirm the new order matches
   the printed order exactly, and confirm the library song count
   is unchanged.
4. Run undo and confirm the original order is restored exactly.
5. Read `~/Library/Logs/seter-shuffle-python/run.log` and confirm
   every step shows GATE OK, or that any GATE FAILED line names
   the gate that fired (mode 26).

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
- The dump script escapes backslash, quote, newline, carriage
  return, and tab in track metadata. An exotic control character in
  a track name makes the JSON unparseable, and the Python core then
  refuses to load it: fail-closed, the run stops before any apply,
  but that library would need the offending track renamed before
  the Python build can run at all.
- Backup files from before the hashed naming (mode 21) are not
  found by the new `./run.sh undo`, because it computes the new
  name. They are still valid: call undo.applescript directly with
  the old file path.
