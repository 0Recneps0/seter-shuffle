-- apply-order.applescript (SeTeR Shuffle, Python experimental core)
--
-- SAFETY GUARANTEES (read these before changing this file):
--  * Only a regular user playlist is ever modified. The Library
--    itself, smart playlists, and folder playlists are refused
--    before anything changes, and the target is checked again
--    inside every restore. "Delete" here always means "remove a
--    song entry from this playlist": deleting a track from a user
--    playlist never deletes the song from the library. No line in
--    this file ever deletes from library playlist 1.
--  * BUILD MAPPING IS MEASURED ON A SORT-MATCHED THROWAWAY, NEVER
--    ON THE TARGET AND NEVER ON A FRESH PLAYLIST. On 2026-10-28
--    the .4 bridge failed on a real 806-song playlist in a loop,
--    and the .5 bridge then failed the same way even though its
--    fresh 3-song probe reported "forward": a fresh playlist does
--    not share the real playlist's sort. The user then confirmed
--    the real playlist is sorted in Music by playlist order
--    DESCENDING, and a read-only diagnostic showed its current
--    list read is the exact reverse of the original backup while
--    its first list track carries index 1, which kills the
--    track-index-as-manual-order idea outright (see
--    seter_shuffle/order_direction.py's mapping section). So
--    run.sh first runs bridge/sort-probe on a throwaway the user
--    set to the SAME sort as the target (Playlist Order
--    descending), and passes the measured mapping here:
--    "forward" (building X lands list read X) or "reversed"
--    (building X lands list read reverse(X)). Build order is the
--    desired list-read order for "forward" and its reverse for
--    "reversed"; verification ALWAYS compares the list read
--    against the desired order, never against the duplicate
--    order. There is NO mapping argument for "other": a
--    sort-probe that returns anything but forward/reversed
--    refuses the build upstream, and this script refuses any
--    other mapping string here. There is NO flip-on-failure
--    for a BUILD: a failed verify never retries the desired
--    order under the opposite mapping, because a wrong flip on
--    a real playlist is exactly the .4 bug, and a failed build
--    still exits non-zero and records nothing. A RESTORE is
--    different, and that distinction is load-bearing (2026-10-29,
--    mode 41): a restore's only job is to return to a KNOWN
--    snapshot, and each restore attempt is verified against
--    that snapshot before it counts. So a restore tries BOTH
--    mappings, given first then opposite, and only declares
--    CRITICAL if neither verifies (see tryRestoreBothMappings).
--    Without that, a build that failed precisely because its
--    mapping was wrong traps its own restore, which used the
--    same wrong mapping: that is exactly what happened on
--    2026-10-29 18:59 PT, when a forward trial-dedupe build
--    verified-failed under the playlist's true reversed
--    mapping, then its forward restore verified-failed too.
--    The old probe-order script is now a standalone manual
--    sanity check only; no build consults it.
--  * Nothing is deleted until a backup exists AND has been verified:
--    the pre-change IDs are written to a temporary file, atomically
--    renamed into place, re-read, and compared exactly to the
--    playlist as it stood. A failed or mismatched backup aborts
--    with the playlist untouched. The old backup file is never
--    truncated in place, so a failed backup write cannot destroy
--    the previous backup. NOTE: the backup is a LIST-READ snapshot,
--    not a display order. Under "read-reversed" it is the reverse of
--    the display order, and the restore formulas below already
--    account for that; never "correct" a backup by reversing it.
--  * The order is validated before any change: non-empty, no blank
--    lines, no whitespace in an ID. Duplicates are refused by
--    default; they are allowed ONLY when run.sh passes the duplicate
--    allowance flag, which it does only for a one-playlist shuffle
--    whose dump itself repeats that ID (a real playlist may hold
--    the same song twice). An empty order is refused outright:
--    there is no "apply an empty order" operation, so a truncated
--    order file can never wipe a playlist.
--  * After building, the playlist must verify exactly against the
--    desired list-read order (see buildForMapping). A count-only
--    check is NOT enough. Any mismatch, any song that could not
--    be found in the
--    library, or any library shrink during the run restores the
--    playlist from the backup and exits non-zero.
--  * DELETE-EMPTY VERIFICATION (2026-10-29 doubling failure): a
--    delete that is assumed but not verified is now a known-unsafe
--    step. Between the 00:21 diagnostic (806 songs) and the 00:41
--    run on 2026-10-29, "My New Sandwich Recipe" doubled to 1612
--    entries, exactly two copies of each song in reverse-backup
--    order twice: consistent with a rebuild duplicating a full
--    copy on top of entries a lagging delete had not removed.
--    The mechanism is unproven, but the guard does not depend on
--    it: every rebuild here first deletes, then RE-READS the
--    playlist and confirms it holds 0 song entries, retrying the
--    delete up to 5 times with a 5-second settle delay between
--    attempts (deletePlaylistSongs). If entries remain after the
--    retries, NOTHING is duplicated into the playlist: the run
--    aborts, restoring from the verified backup only if the
--    playlist was actually changed (a partial delete), and
--    reporting "playlist unchanged" if it was not. A build that
--    duplicates into a non-empty playlist can never happen from
--    this script again, whatever made the delete lag.
--  * Any error after changes start triggers a restore attempt, and
--    the script still exits non-zero. The restore tries BOTH
--    mappings (see tryRestoreBothMappings): a restore under a
--    wrong mapping cannot verify, by the same mechanism as the
--    build failure, so a single-mapping restore would trap
--    itself. If the restore fails under both mappings, the
--    error says so loudly and names the backup file, so the
--    user can re-run undo.applescript with it.
--  * Non-song entries in the playlist (videos, etc.) are never
--    deleted and are left in place; only song entries are managed,
--    and only song entries are verified.
--  * Build and restore loops run inside `with timeout of 3600
--    seconds` blocks. The failed .4 run took about 2 minutes per
--    build for 806 songs; a large playlist must not be cut off by
--    AppleScript's default timeout mid-build.
--
-- THE ONE CASE APPLESCRIPT CANNOT FULLY COVER: if the machine loses
-- power, or Music is force-quit, in the middle of the delete/re-add
-- loop, this script cannot run its restore. What survives is the
-- verified backup file (written and renamed before any change), in
-- the state directory. Recovery is: re-run undo.applescript with
-- that backup file (via run.sh). It restores the playlist to its
-- pre-change state. That is why the backup is written first and
-- verified, and why run.sh also attempts a restore if this script
-- fails.
--
-- MAPPING FRESHNESS, STATED AS AN ASSUMPTION: the mapping is only
-- valid while the target's sort matches the sort-matched
-- throwaway's sort. run.sh enforces a 24-hour freshness window on
-- the recorded mapping and refuses to build without one; if the
-- target's sort may have changed since the probe, re-probe first.
-- A stale mapping is a wrong mapping, and a build under it would
-- fail verification and restore, not silently land a wrong order.
--
-- Usage (always via run.sh, which sort-probes first):
--   osascript apply-order.applescript <playlist-name> <order-txt> <backup-txt> <mapping> [allow-duplicates] [expected-library-song-count] [stamp-1-or-0]
-- mapping: "forward" or "reversed" (from bridge/sort-probe on a
--   throwaway carrying the target's sort; required, never
--   defaulted). An old call passing a probe mode (forward /
--   insert-reversed / read-reversed) or a sort class as the 4th
--   argument fails loudly (see the argument check in `on run`).
-- order-txt: one persistent ID per line (written by the Python CLI).
-- backup-txt: where the verified pre-change IDs are saved; undo
--   reads the same file. The backup path must differ from the order
--   path. allow-duplicates: "1" only for one-playlist shuffles (see
--   above); anything else, including omission, refuses duplicate
--   order IDs. The optional expected-library-song-count is the song
--   count of a WHOLE-LIBRARY dump only: if the library now holds
--   fewer tracks than that, the library shrank since the dump and
--   the run aborts untouched. run.sh omits it for one-playlist
--   shuffles, where the dump count is a playlist count, not a
--   library count, and the mid-run library-size check below still
--   applies.
--
-- UNVERIFIED ON A MAC (see BRIDGE-SAFETY.md): every Music
-- interaction here. The Python core was tested on Linux; this
-- script was not, because this machine has no Music app or osascript.
-- Treat it as reviewed, not tested, until the Mac verification
-- procedure in BRIDGE-SAFETY.md has been run, starting with the
-- sort-matched throwaway probe.

on run argv
	if (count of argv) < 4 then
		error "apply-order.applescript: usage: <playlist-name> <order-txt> <backup-txt> <mapping> [allow-duplicates] [expected-library-song-count] (mapping is required: run via run.sh, which sort-probes first)" number 1
	end if
	set playlistName to item 1 of argv
	set orderPath to item 2 of argv
	set backupPath to item 3 of argv
	set buildMapping to my parseMapping(item 4 of argv)
	if playlistName is "" then
		error "apply-order: playlist name must not be empty." number 1
	end if
	if backupPath is orderPath then
		error "apply-order: backup path must differ from order path, or a failed run could destroy the order file." number 1
	end if
	set allowDuplicates to false
	if (count of argv) > 4 and (item 5 of argv) is "1" then set allowDuplicates to true
	set expectedLibSongs to missing value
	if (count of argv) > 5 and (item 6 of argv) is not "" then
		try
			set expectedLibSongs to (item 6 of argv) as integer
		on error
			error "apply-order: expected library song count must be a number." number 1
		end try
	end if
	-- Description stamp flag (7th argument, run.sh only): "1"
	-- stamps the playlist description after a verified apply,
	-- "0" or absent does not. The stamp is best-effort and never
	-- fails an already-verified apply (see the stamp step after
	-- verification, below). Undo/restore never call this script,
	-- and run.sh passes "0" for dedupe/rediscover, so a stamp can
	-- only ever follow a verified shuffle or flow apply.
	set stampDescription to false
	if (count of argv) > 6 and (item 7 of argv) is "1" then set stampDescription to true

	-- Validate the order BEFORE resolving or changing anything.
	set orderIDs to my readOrderFile(orderPath, allowDuplicates)
	if (count of orderIDs) is 0 then
		error "apply-order: empty order file: refusing to wipe a playlist to empty." number 1
	end if
	set wanted to count of orderIDs

	set destPl to my resolvePlaylist(playlistName, true)
	my assertUserPlaylist(destPl)

	-- The mapping was measured on a sort-matched throwaway by
	-- run.sh before this script runs; there is nothing further to
	-- classify on the target itself, and the target is never used
	-- as its own probe. If the target's sort has changed since the
	-- probe, the build below fails verification and restores.

	-- Library-shrink check against a whole-library dump, before any
	-- change. (Omitted for one-playlist shuffles: there the dump
	-- count is a playlist count, and comparing it to the library
	-- size would be meaningless. The mid-run check below still runs.)
	if expectedLibSongs is not missing value then
		set libNow to my librarySize()
		if libNow < expectedLibSongs then
			error "apply-order: library shrank since the dump (dump had " & expectedLibSongs & " songs, library now has " & libNow & " tracks); refusing, playlist untouched." number 1
		end if
	end if

	-- Snapshot BEFORE any change, and verify the snapshot itself.
	-- This snapshot is a list-read snapshot; see the header note.
	-- For a playlist created by this run (a flow into a missing
	-- playlist), the snapshot is legitimately empty: playlistIDs
	-- returns {} when the bulk read fails but the unfiltered
	-- track count is 0 (2026-10-29, mode 34). Nothing is
	-- duplicated until the delete-empty verification passes, so
	-- an empty snapshot cannot wipe anything that existed.
	set backupIDs to my playlistIDs(destPl)
	my writeBackupAtomically(backupPath, backupIDs)

	set libBefore to my librarySize()

	-- Build with the measured mapping and verify against the
	-- desired list-read order. A false result here means the
	-- build could not be proven, and the only safe next step is
	-- the backup restore. There is no flip: a failed verify never
	-- retries with the opposite mapping.
	set buildResult to my buildAndVerifyMapping(destPl, orderIDs, buildMapping)
	if not (ok of buildResult) then
		set buildFailed to failed of buildResult
		-- Delete-empty failure: nothing was duplicated (see
		-- deletePlaylistSongs). Restore only if the playlist was
		-- actually changed (a partial delete); if it still
		-- matches the backup exactly, it is unchanged and no
		-- restore is needed or attempted.
		if buildFailed contains "delete-not-empty" then
			if my verifyAgainst(destPl, backupIDs) then
				error "apply-order: delete did not take effect after retries (playlist still holds song entries); nothing was duplicated and the playlist is unchanged. Backup at " & backupPath & ". Do not re-run until the delete works on a throwaway." number 1
			end if
			set restoreResult to my tryRestoreBothMappings(destPl, backupIDs, buildMapping)
			if ok of restoreResult then
				error "apply-order: delete did not take effect after retries, so nothing was applied; playlist restored from backup at " & backupPath & "." number 1
			else
				error "apply-order: CRITICAL: delete did not take effect AND restore failed under both mappings for \"" & playlistName & "\"; playlist may be partial. Re-run undo.applescript with backup " & backupPath & "." number 1
			end if
		end if
		set restoreResult to my tryRestoreBothMappings(destPl, backupIDs, buildMapping)
		if ok of restoreResult then
			if (count of buildFailed) > 0 then
				error "apply-order: " & (count of buildFailed) & " song(s) were not found in the library (" & my joinList(buildFailed) & "); playlist restored from backup at " & backupPath & ", nothing applied." number 1
			else
				error "apply-order: verification failed for \"" & playlistName & "\" (final song order does not match the desired order under mapping " & buildMapping & "); playlist restored from backup at " & backupPath & "." number 1
			end if
		else
			error "apply-order: CRITICAL: build/verification failed AND restore failed under both mappings for \"" & playlistName & "\"; playlist may be partial. Re-run undo.applescript with backup " & backupPath & "." number 1
		end if
	end if
	set libAfter to my librarySize()
	if libAfter < libBefore then
		set restoreResult to my tryRestoreBothMappings(destPl, backupIDs, buildMapping)
		if ok of restoreResult then
			error "apply-order: library shrank during the run; playlist restored from backup at " & backupPath & ", nothing applied." number 1
		else
			error "apply-order: CRITICAL: library shrank during the run AND restore failed under both mappings; playlist may be partial. Re-run undo.applescript with backup " & backupPath & "." number 1
		end if
	end if

	-- Last-reshuffled stamp: ONLY here, after verification and
	-- the library-shrink check have both passed. If Music does
	-- not expose a settable description for this playlist, the
	-- stamp is skipped with a note in the return string and the
	-- apply still succeeds: a cosmetic stamp must never turn a
	-- verified apply into a failure, and it must never run on a
	-- failed or restored playlist (those paths error above,
	-- before this line).
	set stampNote to ""
	if stampDescription then
		try
			tell application "Music"
				set description of destPl to "Last reshuffled: " & (current date as string)
			end tell
			set stampNote to "; playlist description stamped"
		on error errMsg
			set stampNote to "; description stamp skipped (" & errMsg & ")"
		end try
	end if

	return "APPLY OK: applied " & wanted & " songs to \"" & playlistName & "\" in exact order (mapping " & buildMapping & "; backup verified: " & (count of backupIDs) & " songs at " & backupPath & ")" & stampNote
end run

-- The build mapping, validated, never defaulted. It comes from
-- bridge/sort-probe on a throwaway carrying the target's sort
-- (see the header). An old call passing a probe mode
-- (insert-reversed / read-reversed), a sort class
-- (reverse-sorted / other-sort), or anything else must fail here,
-- before anything is resolved or changed. "other" is not a build
-- mapping: a sort-probe that returns "other" refuses the build
-- upstream, and this script refuses it too.
on parseMapping(mappingText)
	if mappingText is "forward" or mappingText is "reversed" then
		return mappingText
	end if
	error "apply-order: unknown or missing build mapping \"" & mappingText & "\" (expected forward or reversed from sort-probe on a sort-matched throwaway; run via run.sh, and re-probe if the target's sort may have changed)." number 1
end parseMapping

on reverseList(a)
	set outList to {}
	repeat with i from (count of a) to 1 by -1
		set end of outList to item i of a
	end repeat
	return outList
end reverseList

-- Mirror of seter_shuffle/order_direction.py's mapping section. If
-- these handlers ever drift from that module, the bridge is wrong
-- even though the Python tests pass, because the tests run here
-- and the bridge runs on a Mac. The mapping is an end-to-end
-- build-to-list mapping measured on a sort-matched throwaway: it
-- already includes whatever the sort, the insert behaviour, and
-- the read behaviour do together, so the build and the verify here
-- need no separate model of any of them.
on buildForMapping(desiredIDs, buildMapping)
	if buildMapping is "reversed" then return my reverseList(desiredIDs)
	return desiredIDs
end buildForMapping

-- Delete the playlist's songs, PROVE the playlist is empty, and
-- only then duplicate the given IDs into it, in the given order.
-- Returns the IDs that could not be found in the library (empty
-- means every song was placed). Never throws for a missing song;
-- the caller decides what a failure means. An outer error (Music
-- quitting mid-build, for example) is reported as a single
-- "rebuild-error" entry, so the caller still restores instead of
-- trusting a partial build. If the delete cannot be verified
-- empty (deletePlaylistSongs), returns {"delete-not-empty"} and
-- duplicates NOTHING: duplicating into a non-empty playlist is
-- how a doubled playlist happens, and it is refused here outright.
on rebuildList(pl, idList)
	set failedIDs to {}
	try
		my assertUserPlaylist(pl)
	on error
		return {"assert-failed"}
	end try
	set emptied to false
	try
		with timeout of 3600 seconds
			set emptied to my deletePlaylistSongs(pl)
		end timeout
	on error
		set emptied to false
	end try
	if not emptied then return {"delete-not-empty"}
	try
		with timeout of 3600 seconds
			tell application "Music"
				repeat with pid in idList
					set pidStr to contents of pid
					try
						set sourceTrack to (first track of library playlist 1 whose persistent ID is pidStr)
						duplicate sourceTrack to pl
					on error
						set end of failedIDs to pidStr
					end try
				end repeat
			end tell
		end timeout
	on error
		set end of failedIDs to "rebuild-error"
	end try
	return failedIDs
end rebuildList

-- Delete-EMPTY verification (2026-10-29 doubling failure; see the
-- header). Deletes the playlist's song entries, then re-reads the
-- playlist and confirms it holds 0 song entries, retrying the
-- delete up to 5 times with a 5-second settle delay between
-- attempts, because a delete at 806-song scale may lag or not
-- take effect before a duplicate loop starts. Returns true only
-- on a verified-empty re-read; returns false (never throws) if
-- entries remain after the retries, if the count cannot be read,
-- or if a delete attempt errors. Callers must treat false as
-- "do not duplicate anything". Non-song entries are never
-- deleted and are not counted: the count filters to song entries
-- only, exactly like every other read in this script.
on deletePlaylistSongs(pl)
	repeat with attempt from 1 to 5
		try
			tell application "Music"
				delete (every track of pl whose media kind is song)
			end tell
		on error
			-- A failed delete event proves nothing about the
			-- playlist's contents; fall through to the re-read,
			-- which is the only evidence this handler trusts.
		end try
		delay 5
		set remaining to -1
		try
			tell application "Music"
				set remaining to count of (every track of pl whose media kind is song)
			end tell
		on error
			-- Filtered count can fail (-1728) on a brand-new
			-- empty playlist (2026-10-29, mode 34); an
			-- unfiltered count of 0 proves it is empty
			-- regardless. Any other value stays a failure:
			-- with a filtered error and tracks present, song
			-- vs non-song entries cannot be distinguished, so
			-- the delete is NOT declared verified.
			set remaining to my playlistTrackCount(pl)
		end try
		if remaining is 0 then return true
	end repeat
	return false
end deletePlaylistSongs

-- Build a desired list-read order under the measured mapping and
-- verify it exactly. Returns {ok:boolean, failed:list}. A false
-- result is never retried with the opposite mapping HERE: that
-- would be guessing a build, and the 2026-10-28 runs are what
-- guessing buys. The caller restores from backup on false, and
-- the restore handler (tryRestoreBothMappings) is the only
-- place the opposite mapping is tried, verified against the
-- snapshot, never to land a desired order.
on buildAndVerifyMapping(pl, desiredIDs, buildMapping)
	set failedIDs to my rebuildList(pl, my buildForMapping(desiredIDs, buildMapping))
	if (count of failedIDs) > 0 then return {ok:false, failed:failedIDs}
	set verified to false
	try
		set verified to my verifyAgainst(pl, desiredIDs)
	on error
		set verified to false
	end try
	if verified then
		return {ok:true, failed:{}}
	else
		return {ok:false, failed:{}}
	end if
end buildAndVerifyMapping

-- Restore a playlist from a list-read snapshot under the measured
-- mapping, then verify exactly. Returns {ok:boolean, failed:list};
-- a failed restore is reported, never claimed as a success.
on tryRestoreMapping(pl, snapshotIDs, buildMapping)
	try
		my assertUserPlaylist(pl)
	on error errMsg
		return {ok:false, failed:{}}
	end try
	return my buildAndVerifyMapping(pl, snapshotIDs, buildMapping)
end tryRestoreMapping

-- The opposite of a mapping: the only other value parseMapping
-- accepts, so this can never invent a third mapping.
on oppositeMapping(buildMapping)
	if buildMapping is "reversed" then return "forward"
	return "reversed"
end oppositeMapping

-- Restore from a list-read snapshot trying BOTH mappings, given
-- first then opposite, each verified against the snapshot.
-- Returns the first successful result, or the second result if
-- both failed. This is a RESTORE retry, not a build flip: it
-- never lands a desired order, it only returns to a snapshot
-- that already existed, and an unverified attempt counts for
-- nothing. It exists because a restore under a wrong mapping
-- cannot verify, by the same mechanism as a build failure
-- under that mapping: on 2026-10-29 18:59 PT a forward
-- trial-dedupe build verified-failed under a reversed sort,
-- then its forward-only restore verified-failed too, and the
-- run declared CRITICAL even though every song was still
-- present (the pre-undo snapshot was the exact reverse of
-- the backup). A second restore attempt under the opposite
-- mapping would have verified. Callers treat a both-failed
-- result as CRITICAL and must not build on top of it.
on tryRestoreBothMappings(pl, snapshotIDs, buildMapping)
	set firstResult to my tryRestoreMapping(pl, snapshotIDs, buildMapping)
	if ok of firstResult then return firstResult
	set otherMapping to my oppositeMapping(buildMapping)
	return my tryRestoreMapping(pl, snapshotIDs, otherMapping)
end tryRestoreBothMappings

-- Resolve a playlist by name without ever guessing. Music can hold
-- two playlists with the same name; a bare `playlist "Name"` lookup
-- would silently pick one of them. So: count the matches. Zero
-- means create (apply only) or error; more than one means refuse;
-- exactly one means use that object, not a fresh name lookup. The
-- object reference is then used for the whole run, so a duplicate
-- name created mid-run cannot redirect the build.
on resolvePlaylist(playlistName, allowCreate)
	tell application "Music"
		set matches to every playlist whose name is playlistName
	end tell
	if (count of matches) is 0 then
		if allowCreate then
			-- Create-then-read fix (2026-10-29, mode 34): a flow
			-- into a playlist that does not exist yet failed at
			-- the first bulk ID read with -1728. The make-new
			-- return value can go stale (Music / iCloud sync
			-- re-identifies the new playlist), so never build
			-- from it blindly: re-resolve the new playlist by
			-- its id with a fresh lookup and use that reference
			-- for the whole run. If the fresh lookup fails, the
			-- run aborts before anything changes.
			tell application "Music"
				set newPl to make new user playlist with properties {name:playlistName}
				set newID to id of newPl
				return first user playlist whose id is newID
			end tell
		else
			error "No playlist named \"" & playlistName & "\"." number 1
		end if
	else if (count of matches) > 1 then
		error "Refusing: " & (count of matches) & " playlists are named \"" & playlistName & "\"; refusing to guess which one you mean. Rename one of them and re-run." number 1
	else
		return item 1 of matches
	end if
end resolvePlaylist

-- A playlist is modifiable only if it is a regular user playlist,
-- not smart, and not the Library itself. Anything else fails closed:
-- if any check cannot be performed, the playlist is refused.
on assertUserPlaylist(pl)
	set plName to "(unknown)"
	tell application "Music"
		try
			set plName to name of pl
		end try
	end tell
	set ok to false
	tell application "Music"
		try
			if (class of pl) is user playlist then
				if not (smart of pl) then
					set libID to id of library playlist 1
					set plID to id of pl
					if plID is not libID then set ok to true
				end if
			end if
		end try
	end tell
	if not ok then error "Refusing to modify \"" & plName & "\": it isn't a regular user playlist (or it is the Library itself), and changing it could remove songs from your library."
end assertUserPlaylist

on librarySize()
	with timeout of 3600 seconds
		tell application "Music"
			return count of tracks of library playlist 1
		end tell
	end timeout
end librarySize

on playlistIDs(pl)
	-- Bulk read under a generous timeout, like the build loops:
	-- a 1612-entry playlist must not be cut off by AppleScript's
	-- default timeout mid-read (a failed read fails the verify,
	-- which restores; a slow read must not be mistaken for one).
	-- Empty-playlist fallback (2026-10-29, mode 34): the filtered
	-- bulk read can fail with -1728 on a brand-new empty playlist
	-- even though it holds nothing. An unfiltered track count of 0
	-- proves the snapshot is empty regardless of the filter, so
	-- that case returns {} instead of failing. Any other failure
	-- rethrows: a non-empty playlist whose IDs cannot be read is
	-- not a playlist to build into, and a snapshot must never be
	-- guessed.
	try
		with timeout of 3600 seconds
			tell application "Music"
				return persistent ID of every track of pl whose media kind is song
			end tell
		end timeout
	on error
		if my playlistTrackCount(pl) is 0 then return {}
		error "apply-order: could not read the playlist's song IDs (bulk read failed and the playlist is not empty); playlist untouched." number 1
	end try
end playlistIDs

-- Unfiltered track count, or -1 if even that cannot be read.
-- Used only as the empty proof in playlistIDs and in the
-- delete-empty re-read: count 0 means no tracks at all, hence
-- no songs, whatever the filtered reads do on a fresh playlist.
on playlistTrackCount(pl)
	try
		tell application "Music"
			return count of tracks of pl
		end tell
	on error
		return -1
	end try
end playlistTrackCount

on listsEqual(a, b)
	if (count of a) is not (count of b) then return false
	repeat with i from 1 to (count of a)
		if (item i of a) is not (item i of b) then return false
	end repeat
	return true
end listsEqual

on verifyAgainst(pl, expectedIDs)
	set actualIDs to my playlistIDs(pl)
	return my listsEqual(actualIDs, expectedIDs)
end verifyAgainst

on joinList(idList)
	set AppleScript's text item delimiters to ", "
	set t to idList as text
	set AppleScript's text item delimiters to ""
	if (count of t) > 500 then set t to (text 1 thru 500 of t) & "..."
	return t
end joinList

-- Trim spaces, tabs, and carriage returns from both ends. Written
-- as two plain loops so no character of an empty string is ever
-- read: AppleScript does not guarantee short-circuit evaluation of
-- a compound condition, so a condition like "count > 0 and
-- character 1 is a space" could still read character 1 of "".
on trimText(t)
	set spaceChar to " "
	set tabChar to character id 9
	set crChar to character id 13
	repeat while t is not ""
		set firstChar to character 1 of t
		if firstChar is not spaceChar and firstChar is not tabChar and firstChar is not crChar then exit repeat
		if (count of t) is 1 then
			set t to ""
		else
			set t to text 2 thru -1 of t
		end if
	end repeat
	repeat while t is not ""
		set lastChar to character -1 of t
		if lastChar is not spaceChar and lastChar is not tabChar and lastChar is not crChar then exit repeat
		if (count of t) is 1 then
			set t to ""
		else
			set t to text 1 thru -2 of t
		end if
	end repeat
	return t
end trimText

-- Read an ID file strictly: blank lines (other than a single
-- trailing newline, which paragraphs() already drops) and IDs
-- containing whitespace are corruption, not something to skip.
-- An empty file returns {} and the caller decides what that means
-- (apply refuses it; undo accepts it as an empty playlist).
on readIDFileStrict(filePath)
	try
		set raw to do shell script "cat " & quoted form of filePath
	on error errMsg
		error "apply-order: cannot read file " & filePath & ": " & errMsg number 1
	end try
	if raw is "" then return {}
	set AppleScript's text item delimiters to linefeed
	set linesList to paragraphs of raw
	set AppleScript's text item delimiters to ""
	set ids to {}
	repeat with ln in linesList
		set t to my trimText(contents of ln)
		if t is "" then
			error "apply-order: blank line in file " & filePath & ": refusing, the file may be truncated or corrupt." number 1
		end if
		if (t contains " ") or (t contains (character id 9)) or (t contains (character id 13)) then
			error "apply-order: malformed ID in file " & filePath & ": " & t number 1
		end if
		set end of ids to t
	end repeat
	return ids
end readIDFileStrict

-- Order files refuse duplicates by default: the Python core never
-- emits one for a whole-library order, so a duplicate there is
-- corruption, and applying it would create a duplicate playlist
-- entry. The exception is a one-playlist shuffle, whose dump itself
-- repeats an ID for each duplicate playlist entry; run.sh passes
-- the allowance flag only in that case, and only up to the dump's
-- own multiplicity (checked in Python first). Checked with sort |
-- uniq -d (fast even for thousands of songs; an AppleScript nested
-- loop would be O(n^2) and slow on a large library).
on readOrderFile(filePath, allowDuplicates)
	set ids to my readIDFileStrict(filePath)
	if (count of ids) is 0 then return ids
	if allowDuplicates then return ids
	set dupes to ""
	try
		set dupes to do shell script "sort " & quoted form of filePath & " | uniq -d"
	on error errMsg
		error "apply-order: could not check order file for duplicates: " & errMsg number 1
	end try
	if dupes is not "" then
		error "apply-order: duplicate persistent IDs in order file (refusing, applying would duplicate playlist entries): " & dupes number 1
	end if
	return ids
end readOrderFile

on writeIDFile(filePath, idList)
	set AppleScript's text item delimiters to linefeed
	set fileText to idList as text
	set AppleScript's text item delimiters to ""
	set fh to open for access (POSIX file filePath) with write permission
	try
		set eof of fh to 0
		write fileText to fh as «class utf8»
		close access fh
	on error errMsg number errNum
		try
			close access fh
		end try
		error "apply-order: could not write file " & filePath & ": " & errMsg number errNum
	end try
end writeIDFile

-- Write the backup to a temporary file, atomically rename it into
-- place, then re-read it and compare it exactly to the snapshot.
-- The old backup file is never truncated in place, so a failed
-- write leaves the previous backup intact, and a rename is atomic:
-- after it, the backup file is either the old one or the new one,
-- never a half-written one. Any mismatch aborts BEFORE any change.
on writeBackupAtomically(backupPath, idList)
	set tmpPath to backupPath & ".tmp"
	my writeIDFile(tmpPath, idList)
	try
		do shell script "mv -f " & quoted form of tmpPath & " " & quoted form of backupPath
	on error errMsg
		try
			do shell script "rm -f " & quoted form of tmpPath
		end try
		error "apply-order: could not install backup file " & backupPath & " (nothing was changed): " & errMsg number 1
	end try
	set checkIDs to my readIDFileStrict(backupPath)
	if not my listsEqual(checkIDs, idList) then
		error "apply-order: backup verification failed for " & backupPath & " (re-read does not match the playlist snapshot); nothing was changed." number 1
	end if
end writeBackupAtomically
