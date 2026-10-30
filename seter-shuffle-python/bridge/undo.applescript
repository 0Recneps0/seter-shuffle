-- undo.applescript (SeTeR Shuffle, Python experimental core)
--
-- SAFETY GUARANTEES (same contract as apply-order.applescript):
--  * Only a regular user playlist is ever modified, resolved by an
--    unambiguous filtered lookup (two playlists with the same name
--    means refuse, never guess), and checked again inside every
--    restore. The Library itself and smart playlists are refused.
--    "Delete" here always means "remove a song entry from this
--    playlist": it never deletes a song from the library, and no
--    line in this file ever deletes from library playlist 1.
--  * BUILD MAPPING IS MEASURED ON A SORT-MATCHED THROWAWAY, NEVER
--    ON A FRESH PLAYLIST AND NEVER ON THE TARGET. On 2026-10-28 the
--    .4 undo failed on a real 806-song playlist in a loop, and the
--    .5 bridge then failed the same way even though its fresh
--    3-song probe reported "forward": a fresh playlist does not
--    share the real playlist's sort (the user confirmed the real
--    playlist is sorted by playlist order DESCENDING, and a
--    read-only diagnostic showed its list read reversed against
--    the original backup while its first list track carries index
--    1, which kills track index as a manual-order reference). So
--    run.sh first runs bridge/sort-probe on a throwaway the user
--    set to the SAME sort as the target, and passes the measured
--    mapping here: "forward" or "reversed" (see buildForMapping,
--    which mirrors seter_shuffle/order_direction.py's mapping
--    section exactly). Verification ALWAYS compares the list read
--    against the backup order, never against the duplicate order.
--    There is NO flip-on-failure for a BUILD: a failed verify
--    never retries the backup order under the opposite mapping
--    to land it, and still exits non-zero. A RESTORE is
--    different (2026-10-29, mode 41): its only job is to return
--    to a KNOWN snapshot, each attempt verified against that
--    snapshot, so the pre-undo restore tries BOTH mappings,
--    given first then opposite (see tryRestoreBothMappings),
--    and only declares CRITICAL if neither verifies. Without
--    that, a restore under a wrong mapping cannot verify, by
--    the same mechanism as the build failure, and traps itself:
--    on 2026-10-29 18:59 PT a forward trial-dedupe build
--    verified-failed under a reversed sort, then its
--    forward-only restore and the undo restore both
--    verified-failed too, even though every song was present.
--  * The backup file is validated BEFORE anything is deleted: it
--    must exist and be readable, with no blank lines in the middle
--    and no whitespace inside an ID. A missing or corrupt backup
--    aborts with the playlist untouched. NOTE: the backup is a
--    LIST-READ snapshot, not a display order. Under "read-reversed"
--    it is the reverse of the display order, and the restore
--    formulas below already account for that; never "correct" a
--    backup by reversing it.
--  * Before deleting anything, the playlist's CURRENT state is
--    snapshotted to a separate pre-undo backup file, written
--    atomically and verified by re-reading it. The old undo script
--    deleted first and asked questions later: if the rebuild then
--    failed, the pre-undo playlist was already gone. That cannot
--    happen here: a failed undo restores from the pre-undo snapshot,
--    and if even that fails, both backup paths are named loudly in
--    the error.
--  * After rebuilding, the playlist must verify exactly against
--    the backup order under the measured mapping. Any mismatch or
--    any backup song missing from the
--    library triggers a restore from the pre-undo snapshot and a
--    non-zero exit.
--  * An empty backup file is legitimate: it snapshots an empty
--    playlist (a first-run playlist), so undo of an empty backup
--    restores an empty playlist and succeeds. A backup file that
--    contains duplicate IDs is also legitimate: a real playlist
--    can hold the same song twice, and undo reproduces it exactly.
--  * DELETE-EMPTY VERIFICATION (2026-10-29 doubling failure): the
--    same guard as apply-order. A delete that is assumed but not
--    verified is a known-unsafe step after a real playlist doubled
--    to 1612 entries (each song twice) between the 00:21 diagnostic
--    and the 00:41 run on 2026-10-29, consistent with a rebuild
--    duplicating on top of entries a lagging delete had not
--    removed. Every rebuild here deletes, re-reads, and confirms
--    0 song entries, retrying up to 5 times with a 5-second settle
--    delay (deletePlaylistSongs); if entries remain, nothing is
--    duplicated, and the run restores the pre-undo snapshot only
--    if the playlist was actually changed, or reports it unchanged
--    if it was not.
--  * Non-song entries in the playlist are never deleted and are
--    left in place; only song entries are managed and verified.
--  * Build and restore loops run inside `with timeout of 3600
--    seconds` blocks, so a large playlist is not cut off by
--    AppleScript's default timeout mid-build.
--
-- THE ONE CASE APPLESCRIPT CANNOT FULLY COVER: if the machine loses
-- power, or Music is force-quit, in the middle of the delete/re-add
-- loop, this script cannot run its restore. What survives is the
-- pre-undo backup file (written and verified before any change) in
-- the state directory, plus the original backup file, which undo
-- never overwrites. Recovery is: re-run undo.applescript with the
-- original backup file (via run.sh, which sort-probes first). If
-- the playlist is left partial, re-running undo is safe to repeat:
-- it always snapshots first.
--
-- Usage (always via run.sh, which sort-probes first):
--   osascript undo.applescript <playlist-name> <backup-txt> <mapping> [pre-undo-backup-txt]
-- mapping: "forward" or "reversed" (from bridge/sort-probe on a
--   throwaway carrying the target's sort; required, never
--   defaulted, so an unprobed call fails loudly instead of
--   building with a guessed mapping).
-- backup-txt: one persistent ID per line, in list-read snapshot
--   order. An empty file restores an empty playlist. If the pre-undo
--   path is omitted it defaults to <backup-txt>.pre-undo. The
--   pre-undo path must differ from the backup path, or the original
--   backup would be overwritten before it is used.
--
-- UNVERIFIED ON A MAC (see BRIDGE-SAFETY.md): every Music
-- interaction here. The Python core was tested on Linux; this
-- script was not, because this machine has no Music app or osascript.
-- Treat it as reviewed, not tested, until the Mac verification
-- procedure in BRIDGE-SAFETY.md has been run, starting with the
-- sort-matched throwaway probe.

on run argv
	if (count of argv) < 3 then
		error "undo.applescript: usage: <playlist-name> <backup-txt> <mapping> [pre-undo-backup-txt] (mapping is required: run via run.sh, which sort-probes first)" number 1
	end if
	set playlistName to item 1 of argv
	set backupPath to item 2 of argv
	set buildMapping to my parseMapping(item 3 of argv)
	set preUndoPath to backupPath & ".pre-undo"
	if (count of argv) > 3 then set preUndoPath to item 4 of argv
	if playlistName is "" then
		error "undo: playlist name must not be empty." number 1
	end if
	if preUndoPath is backupPath then
		error "undo: pre-undo backup path must differ from the backup path, or the original backup would be overwritten before it is used." number 1
	end if

	-- Validate the backup BEFORE resolving or changing anything.
	set backupIDs to my readBackupFile(backupPath)

	set destPl to my resolvePlaylist(playlistName)
	my assertUserPlaylist(destPl)

	-- Snapshot the CURRENT playlist first, atomically and verified.
	-- This is what makes a failed undo recoverable. A failure
	-- here happens BEFORE any change, so it is marked
	-- PLAYLIST_UNTOUCHED: run.sh's post-apply restore path reads
	-- that marker to tell "undo failed before touching anything"
	-- apart from "undo failed after changes started", instead of
	-- wrongly reporting every failed restore as "may be partial"
	-- (2026-10-29, mode 36: the .4 Flow restore died at this
	-- snapshot read with -1728 on an empty playlist and was
	-- reported as possibly partial when nothing had changed).
	try
		set currentIDs to my playlistIDs(destPl)
		my writeBackupAtomically(preUndoPath, currentIDs)
	on error errMsg
		error "undo: failed reading the current playlist before any change (PLAYLIST_UNTOUCHED); playlist untouched. Backups: original " & backupPath & ", pre-undo " & preUndoPath & ". Cause: " & errMsg number 1
	end try

	-- Rebuild from the backup under the measured mapping, with
	-- verification against the backup order itself.
	set buildResult to my buildAndVerifyMapping(destPl, backupIDs, buildMapping)
	if not (ok of buildResult) then
		set buildFailed to failed of buildResult
		-- Delete-empty failure: nothing was duplicated (see
		-- deletePlaylistSongs). Restore the pre-undo snapshot only
		-- if the playlist was actually changed (a partial delete);
		-- if it still matches the pre-undo snapshot exactly, it is
		-- unchanged and no restore is needed or attempted.
		if buildFailed contains "delete-not-empty" then
			if my verifyAgainst(destPl, currentIDs) then
				error "undo: delete did not take effect after retries (playlist still holds song entries); nothing was duplicated and the playlist is unchanged. Pre-undo state saved at " & preUndoPath & ". Do not re-run until the delete works on a throwaway." number 1
			end if
			set restoreResult to my tryRestoreBothMappings(destPl, currentIDs, buildMapping)
			if ok of restoreResult then
				error "undo: delete did not take effect after retries, so the backup was not applied; playlist restored to its pre-undo state from " & preUndoPath & "." number 1
			else
				error "undo: CRITICAL: delete did not take effect AND pre-undo restore failed under both mappings; playlist may be partial. Backups: original " & backupPath & ", pre-undo " & preUndoPath & "." number 1
			end if
		end if
		set restoreResult to my tryRestoreBothMappings(destPl, currentIDs, buildMapping)
		if ok of restoreResult then
			if (count of buildFailed) > 0 then
				error "undo: restored " & ((count of backupIDs) - (count of buildFailed)) & " of " & (count of backupIDs) & " songs to \"" & playlistName & "\"; " & (count of buildFailed) & " song(s) were not found in the library (" & my joinList(buildFailed) & "). Playlist restored to its pre-undo state from " & preUndoPath & "; the missing songs cannot be restored until they are back in the library." number 1
			else
				error "undo: verification failed for \"" & playlistName & "\" (final song order does not match the backup order under mapping " & buildMapping & "); playlist restored to its pre-undo state from " & preUndoPath & "." number 1
			end if
		else
			if (count of buildFailed) > 0 then
				error "undo: CRITICAL: " & (count of buildFailed) & " song(s) not found AND pre-undo restore failed under both mappings; playlist may be partial. Backups: original " & backupPath & ", pre-undo " & preUndoPath & "." number 1
			else
				error "undo: CRITICAL: verification failed AND pre-undo restore failed under both mappings for \"" & playlistName & "\"; playlist may be partial. Backups: original " & backupPath & ", pre-undo " & preUndoPath & "." number 1
			end if
		end if
	end if

	if (count of backupIDs) is 0 then
		return "UNDO OK: restored an empty playlist to \"" & playlistName & "\" (backup was empty; pre-undo state saved at " & preUndoPath & ")"
	end if
	return "UNDO OK: restored " & (count of backupIDs) & " songs to \"" & playlistName & "\" in exact backup order (mapping " & buildMapping & "; pre-undo state saved at " & preUndoPath & ")"
end run

-- Resolve by filtered lookup, never by a bare name reference, and
-- never create: undo only ever restores a playlist that exists.
on resolvePlaylist(playlistName)
	tell application "Music"
		set matches to every playlist whose name is playlistName
	end tell
	if (count of matches) is 0 then
		error "undo: no playlist named \"" & playlistName & "\"." number 1
	else if (count of matches) > 1 then
		error "undo: refusing: " & (count of matches) & " playlists are named \"" & playlistName & "\"; refusing to guess which one you mean. Rename one of them and re-run." number 1
	else
		return item 1 of matches
	end if
end resolvePlaylist

-- A playlist is modifiable only if it is a regular user playlist,
-- not smart, and not the Library itself. Anything else, or any
-- check that cannot be performed, fails closed.
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

-- The build mapping, validated, never defaulted. It comes from
-- bridge/sort-probe on a throwaway carrying the target's sort.
-- An old probe mode or sort class here fails loudly.
on parseMapping(mappingText)
	if mappingText is "forward" or mappingText is "reversed" then
		return mappingText
	end if
	error "undo: unknown or missing build mapping \"" & mappingText & "\" (expected forward or reversed from sort-probe on a sort-matched throwaway; run via run.sh, and re-probe if the target's sort may have changed)." number 1
end parseMapping

on reverseList(a)
	set outList to {}
	repeat with i from (count of a) to 1 by -1
		set end of outList to item i of a
	end repeat
	return outList
end reverseList

-- Mirror of seter_shuffle/order_direction.py's mapping section.
on buildForMapping(desiredIDs, buildMapping)
	if buildMapping is "reversed" then return my reverseList(desiredIDs)
	return desiredIDs
end buildForMapping

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
-- header and apply-order.applescript). Deletes, re-reads, and
-- confirms 0 song entries, retrying up to 5 times with a 5-second
-- settle delay. Returns true only on a verified-empty re-read;
-- returns false (never throws) if entries remain, the count cannot
-- be read, or a delete attempt errors. Callers must treat false
-- as "do not duplicate anything".
on deletePlaylistSongs(pl)
	repeat with attempt from 1 to 5
		try
			tell application "Music"
				delete (every track of pl whose media kind is song)
			end tell
		on error
		end try
		delay 5
		set remaining to -1
		try
			tell application "Music"
				set remaining to count of (every track of pl whose media kind is song)
			end tell
		on error
			-- Filtered count can fail (-1728) on a brand-new
			-- empty playlist (2026-10-29, modes 34 and 36); an
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
-- verify it exactly. Returns {ok:boolean, failed:list}. No flip
-- on failure for the build itself: the caller restores from the
-- pre-undo snapshot, trying both mappings (tryRestoreBothMappings),
-- each verified against that snapshot, before declaring CRITICAL.
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

-- Restore from a list-read snapshot under the measured mapping.
-- Returns {ok:boolean, failed:list}; a failed restore is reported,
-- never claimed as a success.
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
-- nothing. It exists for the 2026-10-29 mode 41 trap: a restore
-- under a wrong mapping cannot verify, by the same mechanism
-- as a build failure under that mapping, so a single-mapping
-- restore traps itself and wrongly declares a playlist partial
-- when every song is still present, merely reversed.
on tryRestoreBothMappings(pl, snapshotIDs, buildMapping)
	set firstResult to my tryRestoreMapping(pl, snapshotIDs, buildMapping)
	if ok of firstResult then return firstResult
	set otherMapping to my oppositeMapping(buildMapping)
	return my tryRestoreMapping(pl, snapshotIDs, otherMapping)
end tryRestoreBothMappings

on playlistIDs(pl)
	-- Bulk read under a generous timeout, like the build loops:
	-- a 1612-entry playlist must not be cut off by AppleScript's
	-- default timeout mid-read (a failed read fails the verify,
	-- which restores; a slow read must not be mistaken for one).
	-- Empty-playlist fallback (2026-10-29, modes 34 and 36): the
	-- filtered bulk read can fail with -1728 on a brand-new empty
	-- playlist even though it holds nothing. An unfiltered track
	-- count of 0 proves the snapshot is empty regardless of the
	-- filter, so that case returns {} instead of failing. This
	-- was missing here in .4, so undo died at its very first
	-- step (the pre-undo snapshot read) on the empty "SeTeR Flow"
	-- playlist with -1728, before changing anything. Any other
	-- failure rethrows: a non-empty playlist whose IDs cannot be
	-- read is not a playlist to build into, and a snapshot must
	-- never be guessed.
	try
		with timeout of 3600 seconds
			tell application "Music"
				return persistent ID of every track of pl whose media kind is song
			end tell
		end timeout
	on error
		if my playlistTrackCount(pl) is 0 then return {}
		error "undo: could not read the playlist's song IDs (bulk read failed and the playlist is not empty); playlist untouched." number 1
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

-- Backup files allow duplicate IDs (a real playlist can hold the
-- same song twice) and allow an empty file (an empty playlist), but
-- refuse blank lines in the middle and whitespace inside an ID.
on readBackupFile(filePath)
	try
		set raw to do shell script "cat " & quoted form of filePath
	on error errMsg
		error "undo: cannot read backup file " & filePath & ": " & errMsg number 1
	end try
	if raw is "" then return {}
	set AppleScript's text item delimiters to linefeed
	set linesList to paragraphs of raw
	set AppleScript's text item delimiters to ""
	set ids to {}
	repeat with ln in linesList
		set t to my trimText(contents of ln)
		if t is "" then
			error "undo: blank line in backup file " & filePath & ": refusing, the file may be truncated or corrupt." number 1
		end if
		if (t contains " ") or (t contains (character id 9)) or (t contains (character id 13)) then
			error "undo: malformed ID in backup file " & filePath & ": " & t number 1
		end if
		set end of ids to t
	end repeat
	return ids
end readBackupFile

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
		error "undo: could not write file " & filePath & ": " & errMsg number errNum
	end try
end writeIDFile

-- Atomic install + re-read verification, same as apply-order: the
-- old file is never truncated in place, so a failed write leaves
-- the previous file intact, and a rename is atomic.
on writeBackupAtomically(backupPath, idList)
	set tmpPath to backupPath & ".tmp"
	my writeIDFile(tmpPath, idList)
	try
		do shell script "mv -f " & quoted form of tmpPath & " " & quoted form of backupPath
	on error errMsg
		try
			do shell script "rm -f " & quoted form of tmpPath
		end try
		error "undo: could not install pre-undo backup file " & backupPath & " (nothing was changed): " & errMsg number 1
	end try
	set checkIDs to my readBackupFile(backupPath)
	if not my listsEqual(checkIDs, idList) then
		error "undo: pre-undo backup verification failed for " & backupPath & " (re-read does not match the playlist snapshot); nothing was changed." number 1
	end if
end writeBackupAtomically
