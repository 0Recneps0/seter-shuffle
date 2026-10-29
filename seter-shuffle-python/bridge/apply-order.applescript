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
--  * ORDER DIRECTION IS PROBED, NEVER GUESSED. On 2026-10-28 this
--    script's predecessor failed on a real 806-song playlist in a
--    loop: apply, its restore, and undo all failed exact-order
--    verification, and the pre-undo snapshot pulled off that Mac was
--    the EXACT REVERSE of the original backup. Either duplicating
--    inserts at the top of the playlist, or the every-track read
--    returns tracks reversed; the backup files alone cannot tell
--    which. So run.sh runs probe-order.applescript first and passes
--    its verdict here as the mode argument. The mode decides both
--    the duplicate order and the verify expectation (see
--    buildForApply / expectedForApply / buildForRestore /
--    expectedForRestore, which mirror seter_shuffle/order_direction.py
--    exactly). An unknown, missing, or ambiguous mode aborts before
--    anything changes. There is NO flip-on-failure fallback in this
--    script: a failed verify restores from backup and exits
--    non-zero, because a wrong flip on a real playlist is exactly
--    the .4 bug.
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
--  * After building, the playlist must verify exactly under the
--    probed mode (see expectedForApply). A count-only check is NOT
--    enough. Any mismatch, any song that could not be found in the
--    library, or any library shrink during the run restores the
--    playlist from the backup and exits non-zero.
--  * Any error after changes start triggers a restore attempt, and
--    the script still exits non-zero. If the restore itself fails,
--    the error says so loudly and names the backup file, so the
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
-- that backup file (via run.sh, so the probe runs again). It
-- restores the playlist to its pre-change state. That is why the
-- backup is written first and verified, and why run.sh also attempts
-- a restore if this script fails.
--
-- Usage (always via run.sh, which probes first):
--   osascript apply-order.applescript <playlist-name> <order-txt> <backup-txt> <mode> [allow-duplicates] [expected-library-song-count]
-- mode: "forward", "insert-reversed", or "read-reversed" (from the
--   probe; required, never defaulted, so an old unprobed call fails
--   loudly instead of building in the wrong direction).
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
-- procedure in BRIDGE-SAFETY.md has been run, starting with the probe.

on run argv
	if (count of argv) < 4 then
		error "apply-order.applescript: usage: <playlist-name> <order-txt> <backup-txt> <mode> [allow-duplicates] [expected-library-song-count] (mode is required: run via run.sh, which probes first)" number 1
	end if
	set playlistName to item 1 of argv
	set orderPath to item 2 of argv
	set backupPath to item 3 of argv
	set orderMode to my parseMode(item 4 of argv)
	if playlistName is "" then
		error "apply-order: playlist name must not be empty." number 1
	end if
	if backupPath is orderPath then
		error "apply-order: backup path must differ from order path, or a failed run could destroy the order file." number 1
	end if
	set allowDuplicates to false
	if (count of argv) > 4 and (item 5 of argv) is "1" then set allowDuplicates to true
	set expectedLibSongs to missing value
	if (count of argv) > 5 then
		try
			set expectedLibSongs to (item 6 of argv) as integer
		on error
			error "apply-order: expected library song count must be a number." number 1
		end try
	end if

	-- Validate the order BEFORE resolving or changing anything.
	set orderIDs to my readOrderFile(orderPath, allowDuplicates)
	if (count of orderIDs) is 0 then
		error "apply-order: empty order file: refusing to wipe a playlist to empty." number 1
	end if
	set wanted to count of orderIDs

	set destPl to my resolvePlaylist(playlistName, true)
	my assertUserPlaylist(destPl)

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
	set backupIDs to my playlistIDs(destPl)
	my writeBackupAtomically(backupPath, backupIDs)

	set libBefore to my librarySize()

	-- Build in the probed direction, collecting failures instead of
	-- silently skipping songs.
	set buildIDs to my buildForApply(orderIDs, orderMode)
	set buildFailed to {}
	try
		with timeout of 3600 seconds
			tell application "Music"
				delete (every track of destPl whose media kind is song)
			end tell
			tell application "Music"
				repeat with pid in buildIDs
					set pidStr to contents of pid
					try
						set sourceTrack to (first track of library playlist 1 whose persistent ID is pidStr)
						duplicate sourceTrack to destPl
					on error
						set end of buildFailed to pidStr
					end try
				end repeat
			end tell
		end timeout
	on error errMsg number errNum
		set restoreResult to my tryRestore(destPl, backupIDs, orderMode)
		if ok of restoreResult then
			error "apply-order: build failed for \"" & playlistName & "\" (" & errMsg & "); playlist restored from backup at " & backupPath & "." number 1
		else
			error "apply-order: CRITICAL: build failed for \"" & playlistName & "\" (" & errMsg & ") AND restore failed (" & my joinList(failed of restoreResult) & "); playlist may be partial. Re-run undo.applescript with backup " & backupPath & "." number 1
		end if
	end try

	if (count of buildFailed) > 0 then
		set restoreResult to my tryRestore(destPl, backupIDs, orderMode)
		if ok of restoreResult then
			error "apply-order: " & (count of buildFailed) & " song(s) were not found in the library (" & my joinList(buildFailed) & "); playlist restored from backup at " & backupPath & ", nothing applied." number 1
		else
			error "apply-order: CRITICAL: " & (count of buildFailed) & " song(s) not found AND restore failed; playlist may be partial. Re-run undo.applescript with backup " & backupPath & "." number 1
		end if
	end if

	-- Strict verify under the probed mode: the expected list is NOT
	-- always the order file (under read-reversed it is the reverse
	-- of it). The verify calls themselves are wrapped: if Music
	-- quits during verification, that error must also trigger a
	-- restore, not an unhandled exit that leaves the new playlist
	-- in place.
	set verified to false
	set libAfter to -1
	try
		set libAfter to my librarySize()
		set verified to my verifyAgainst(destPl, my expectedForApply(orderIDs, orderMode))
	on error errMsg
		set restoreResult to my tryRestore(destPl, backupIDs, orderMode)
		if ok of restoreResult then
			error "apply-order: verification could not run for \"" & playlistName & "\" (" & errMsg & "); playlist restored from backup at " & backupPath & "." number 1
		else
			error "apply-order: CRITICAL: verification could not run AND restore failed for \"" & playlistName & "\"; playlist may be partial. Re-run undo.applescript with backup " & backupPath & "." number 1
		end if
	end try
	if not verified then
		set restoreResult to my tryRestore(destPl, backupIDs, orderMode)
		if ok of restoreResult then
			error "apply-order: verification failed for \"" & playlistName & "\" (final song order does not match the probed-mode expectation); playlist restored from backup at " & backupPath & "." number 1
		else
			error "apply-order: CRITICAL: verification failed AND restore failed for \"" & playlistName & "\"; playlist may be partial. Re-run undo.applescript with backup " & backupPath & "." number 1
		end if
	end if
	if libAfter < libBefore then
		set restoreResult to my tryRestore(destPl, backupIDs, orderMode)
		if ok of restoreResult then
			error "apply-order: library shrank during the run; playlist restored from backup at " & backupPath & ", nothing applied." number 1
		else
			error "apply-order: CRITICAL: library shrank during the run AND restore failed; playlist may be partial. Re-run undo.applescript with backup " & backupPath & "." number 1
		end if
	end if

	return "APPLY OK: applied " & wanted & " songs to \"" & playlistName & "\" in exact order (mode " & orderMode & "; backup verified: " & (count of backupIDs) & " songs at " & backupPath & ")"
end run

-- The probe mode, validated, never defaulted. An old call without a
-- mode, or with a mode the probe never emits, must fail here, before
-- anything is resolved or changed.
on parseMode(modeText)
	if modeText is "forward" or modeText is "insert-reversed" or modeText is "read-reversed" then
		return modeText
	end if
	error "apply-order: unknown or missing order mode \"" & modeText & "\" (expected forward, insert-reversed, or read-reversed from the probe; run via run.sh)." number 1
end parseMode

on reverseList(a)
	set outList to {}
	repeat with i from (count of a) to 1 by -1
		set end of outList to item i of a
	end repeat
	return outList
end reverseList

-- Mirror of seter_shuffle/order_direction.py. If these handlers ever
-- drift from that module, the bridge is wrong even though the Python
-- tests pass, because the tests run here and the bridge runs on a Mac.
on buildForApply(orderIDs, orderMode)
	if orderMode is "insert-reversed" then return my reverseList(orderIDs)
	return orderIDs
end buildForApply

on expectedForApply(orderIDs, orderMode)
	if orderMode is "read-reversed" then return my reverseList(orderIDs)
	return orderIDs
end expectedForApply

-- Restore builds: the target is always a list-read snapshot, so the
-- duplicate order is the snapshot under "forward" and its reverse
-- under either reversed mode, and the expected list is always the
-- snapshot itself. (Worked through in order_direction.py.)
on buildForRestore(snapshotIDs, orderMode)
	if orderMode is "forward" then return snapshotIDs
	return my reverseList(snapshotIDs)
end buildForRestore

on expectedForRestore(snapshotIDs, orderMode)
	return snapshotIDs
end expectedForRestore

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
			tell application "Music"
				return make new user playlist with properties {name:playlistName}
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
	tell application "Music"
		return count of tracks of library playlist 1
	end tell
end librarySize

on playlistIDs(pl)
	tell application "Music"
		return persistent ID of every track of pl whose media kind is song
	end tell
end playlistIDs

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

-- Restore a playlist from a list-read snapshot, then verify the
-- result exactly under the probed mode. Returns a record
-- {ok:boolean, failed:list} so the caller can distinguish "restored"
-- from "partially restored" and say so loudly instead of claiming
-- success.
on tryRestore(pl, snapshotIDs, orderMode)
	try
		my assertUserPlaylist(pl)
	on error errMsg
		return {ok:false, failed:{}}
	end try
	set failedIDs to {}
	set restoreIDs to my buildForRestore(snapshotIDs, orderMode)
	try
		with timeout of 3600 seconds
			tell application "Music"
				delete (every track of pl whose media kind is song)
			end tell
			tell application "Music"
				repeat with pid in restoreIDs
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
	on error errMsg
		return {ok:false, failed:failedIDs}
	end try
	if (count of failedIDs) > 0 then return {ok:false, failed:failedIDs}
	-- Verify without throwing: if Music is gone, the restore did not
	-- prove itself, and the caller must hear "failed", not a raw
	-- Music error that hides whether a restore was attempted.
	set verified to false
	try
		set verified to my verifyAgainst(pl, my expectedForRestore(snapshotIDs, orderMode))
	on error
		set verified to false
	end try
	if verified then
		return {ok:true, failed:{}}
	else
		return {ok:false, failed:failedIDs}
	end if
end tryRestore

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
