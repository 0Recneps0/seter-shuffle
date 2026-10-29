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
--  * The backup file is validated BEFORE anything is deleted: it
--    must exist and be readable, with no blank lines in the middle
--    and no whitespace inside an ID. A missing or corrupt backup
--    aborts with the playlist untouched.
--  * Before deleting anything, the playlist's CURRENT state is
--    snapshotted to a separate pre-undo backup file, written
--    atomically and verified by re-reading it. The old undo script
--    deleted first and asked questions later: if the rebuild then
--    failed, the pre-undo playlist was already gone. That cannot
--    happen here: a failed undo restores from the pre-undo
--    snapshot, and if even that fails, both backup paths are named
--    loudly in the error.
--  * After rebuilding, the playlist's song IDs must equal the
--    backup IDs exactly, in exactly the backup order. Any mismatch
--    or any backup song missing from the library triggers a
--    restore from the pre-undo snapshot and a non-zero exit.
--  * An empty backup file is legitimate: it snapshots an empty
--    playlist (a first-run playlist), so undo of an empty backup
--    restores an empty playlist and succeeds. A backup file that
--    contains duplicate IDs is also legitimate: a real playlist
--    can hold the same song twice, and undo reproduces it exactly.
--  * Non-song entries in the playlist are never deleted and are
--    left in place; only song entries are managed and verified.
--
-- THE ONE CASE APPLESCRIPT CANNOT FULLY COVER: if the machine loses
-- power, or Music is force-quit, in the middle of the delete/re-add
-- loop, this script cannot run its restore. What survives is the
-- pre-undo backup file (written and verified before any change) in
-- the state directory, plus the original backup file, which undo
-- never overwrites. Recovery is: re-run undo.applescript with the
-- original backup file. If the playlist is left partial, re-running
-- undo is safe to repeat: it always snapshots first.
--
-- Usage:
--   osascript undo.applescript <playlist-name> <backup-txt> [pre-undo-backup-txt]
-- backup-txt: one persistent ID per line, in the original order.
--   An empty file restores an empty playlist. If the pre-undo path
--   is omitted it defaults to <backup-txt>.pre-undo. The pre-undo
--   path must differ from the backup path, or the original backup
--   would be overwritten before it is used.
--
-- UNVERIFIED ON A MAC (see BRIDGE-SAFETY.md): every Music
-- interaction here. The Python core was tested on Linux; this
-- script was not, because this machine has no Music app or
-- osascript. Treat it as reviewed, not tested, until the Mac
-- verification procedure in BRIDGE-SAFETY.md has been run.

on run argv
	if (count of argv) < 2 then
		error "undo.applescript: usage: <playlist-name> <backup-txt> [pre-undo-backup-txt]" number 1
	end if
	set playlistName to item 1 of argv
	set backupPath to item 2 of argv
	set preUndoPath to backupPath & ".pre-undo"
	if (count of argv) > 2 then set preUndoPath to item 3 of argv
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
	-- This is what makes a failed undo recoverable.
	set currentIDs to my playlistIDs(destPl)
	my writeBackupAtomically(preUndoPath, currentIDs)

	-- Rebuild from the backup, collecting failures instead of
	-- silently skipping songs that left the library.
	set buildFailed to {}
	try
		tell application "Music"
			delete (every track of destPl whose media kind is song)
		end tell
		tell application "Music"
			repeat with pid in backupIDs
				set pidStr to contents of pid
				try
					set sourceTrack to (first track of library playlist 1 whose persistent ID is pidStr)
					duplicate sourceTrack to destPl
				on error
					set end of buildFailed to pidStr
				end try
			end repeat
		end tell
	on error errMsg number errNum
		set restoreResult to my tryRestore(destPl, currentIDs)
		if ok of restoreResult then
			error "undo: rebuild failed for \"" & playlistName & "\" (" & errMsg & "); playlist restored to its pre-undo state from " & preUndoPath & "." number 1
		else
			error "undo: CRITICAL: rebuild failed for \"" & playlistName & "\" (" & errMsg & ") AND pre-undo restore failed; playlist may be partial. Backups: original " & backupPath & ", pre-undo " & preUndoPath & "." number 1
		end if
	end try

	if (count of buildFailed) > 0 then
		set restoreResult to my tryRestore(destPl, currentIDs)
		if ok of restoreResult then
			error "undo: restored " & ((count of backupIDs) - (count of buildFailed)) & " of " & (count of backupIDs) & " songs to \"" & playlistName & "\"; " & (count of buildFailed) & " song(s) were not found in the library (" & my joinList(buildFailed) & "). Playlist restored to its pre-undo state from " & preUndoPath & "; the missing songs cannot be restored until they are back in the library." number 1
		else
			error "undo: CRITICAL: " & (count of buildFailed) & " song(s) not found AND pre-undo restore failed; playlist may be partial. Backups: original " & backupPath & ", pre-undo " & preUndoPath & "." number 1
		end if
	end if

	set verified to false
	try
		set verified to my verifyExactOrder(destPl, backupIDs)
	on error errMsg
		set restoreResult to my tryRestore(destPl, currentIDs)
		if ok of restoreResult then
			error "undo: verification could not run for \"" & playlistName & "\" (" & errMsg & "); playlist restored to its pre-undo state from " & preUndoPath & "." number 1
		else
			error "undo: CRITICAL: verification could not run AND pre-undo restore failed for \"" & playlistName & "\"; playlist may be partial. Backups: original " & backupPath & ", pre-undo " & preUndoPath & "." number 1
		end if
	end try
	if not verified then
		set restoreResult to my tryRestore(destPl, currentIDs)
		if ok of restoreResult then
			error "undo: verification failed for \"" & playlistName & "\" (final song order does not exactly match the backup); playlist restored to its pre-undo state from " & preUndoPath & "." number 1
		else
			error "undo: CRITICAL: verification failed AND pre-undo restore failed for \"" & playlistName & "\"; playlist may be partial. Backups: original " & backupPath & ", pre-undo " & preUndoPath & "." number 1
		end if
	end if

	if (count of backupIDs) is 0 then
		return "UNDO OK: restored an empty playlist to \"" & playlistName & "\" (backup was empty; pre-undo state saved at " & preUndoPath & ")"
	end if
	return "UNDO OK: restored " & (count of backupIDs) & " songs to \"" & playlistName & "\" in exact backup order (pre-undo state saved at " & preUndoPath & ")"
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

on verifyExactOrder(pl, expectedIDs)
	set actualIDs to my playlistIDs(pl)
	return my listsEqual(actualIDs, expectedIDs)
end verifyExactOrder

-- Restore from an in-memory ID list and verify exactly. Returns a
-- record {ok:boolean, failed:list}; a failed restore is reported,
-- never claimed as a success.
on tryRestore(pl, idList)
	try
		my assertUserPlaylist(pl)
	on error errMsg
		return {ok:false, failed:{}}
	end try
	set failedIDs to {}
	try
		tell application "Music"
			delete (every track of pl whose media kind is song)
		end tell
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
	on error errMsg
		return {ok:false, failed:failedIDs}
	end try
	if (count of failedIDs) > 0 then return {ok:false, failed:failedIDs}
	-- Verify without throwing: if Music is gone, the restore did not
	-- prove itself, and the caller must hear "failed", not a raw
	-- Music error that hides whether a restore was attempted.
	set verified to false
	try
		set verified to my verifyExactOrder(pl, idList)
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
