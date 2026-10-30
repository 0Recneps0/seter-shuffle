-- dedupe-in-place.applescript (SeTeR Shuffle, Python core, v3.0.9)
--
-- Remove duplicate entries from a playlist WITHOUT rebuilding
-- it. Spencer set the cap 2026-10-30: dedupe must rebuild his
-- playlist 1-2 times max, and the in-place answer is 0 rebuilds
-- on success: only the duplicate entries themselves are
-- deleted, every other song stays exactly where it was, in
-- whatever order Music holds it. No mapping, no probe, no
-- trial, no sort question at all, because nothing is
-- re-added in any order.
--
-- SAFETY, same model as apply-order:
--  * Only a regular user playlist, never the Library, never
--    smart. Anything else fails closed before any change.
--  * A verified snapshot is written (atomically, re-read and
--    compared) BEFORE any deletion, so a failed run can
--    restore to it.
--  * Deletions are by 1-based position in the song-filtered
--    track list, in strictly descending order, re-fetching
--    the list before each deletion, so deleting a higher
--    position never shifts a lower position still to delete.
--  * Verification after deletion is presence only, per
--    Spencer's 2026-10-30 answer that dedupe need not keep
--    the original order: same count as the unique order, and
--    every desired song present. That also proves no
--    duplicate remains, because the desired IDs are unique
--    and the count matches them exactly.
--  * On verification failure the playlist is restored from
--    the snapshot, trying both mappings, each verified
--    exactly against the snapshot, before declaring CRITICAL.
--    A restore is a rebuild, but it only ever happens on a
--    failed run: success costs 0 rebuilds, failure costs at
--    most the restore attempts.
--  * Deleting from a playlist never deletes from the library.
--
-- Usage (always via run.sh):
--   osascript dedupe-in-place.applescript <playlist-name> <unique-order-txt> <delete-indices-txt> <backup-txt>
-- unique-order-txt: one persistent ID per line, unique, the
--   songs that must remain. delete-indices-txt: one integer
--   per line, strictly descending, 1-based positions of the
--   duplicate entries in the song-filtered track list, as
--   computed by run.sh from the same dump the order came
--   from. backup-txt: where the verified pre-change IDs are
--   saved; undo reads the same file.
--
-- UNVERIFIED ON A MAC: every Music interaction here, like
-- every other bridge script. The Python core was tested on
-- Linux; this script was not, because this machine has no
-- Music app or osascript. Treat it as reviewed, not tested,
-- until Spencer runs it on a real doubled playlist.

on run argv
	if (count of argv) < 4 then
		error "dedupe-in-place.applescript: usage: <playlist-name> <unique-order-txt> <delete-indices-txt> <backup-txt>" number 1
	end if
	set playlistName to item 1 of argv
	set orderPath to item 2 of argv
	set indicesPath to item 3 of argv
	set backupPath to item 4 of argv
	if playlistName is "" then
		error "dedupe-in-place: playlist name must not be empty." number 1
	end if
	if backupPath is orderPath or backupPath is indicesPath then
		error "dedupe-in-place: backup path must differ from the order and indices paths, or a failed run could destroy its own inputs." number 1
	end if

	set orderIDs to my readIDFileStrict(orderPath)
	if (count of orderIDs) is 0 then
		error "dedupe-in-place: empty unique order file: refusing to wipe a playlist to empty." number 1
	end if
	set deleteIndices to my readIndicesFile(indicesPath)
	if (count of deleteIndices) is 0 then
		error "dedupe-in-place: empty delete-indices file: nothing to delete, run.sh should have skipped this run." number 1
	end if

	set destPl to my resolvePlaylist(playlistName, false)
	my assertUserPlaylist(destPl)

	-- Snapshot BEFORE any change, and verify the snapshot
	-- itself (writeBackupAtomically re-reads and compares).
	set backupIDs to my playlistIDs(destPl)
	my writeBackupAtomically(backupPath, backupIDs)
	if (count of backupIDs) - (count of orderIDs) is not (count of deleteIndices) then
		error "dedupe-in-place: delete count does not match the snapshot: snapshot has " & (count of backupIDs) & " songs, unique order has " & (count of orderIDs) & ", but " & (count of deleteIndices) & " deletions were requested; playlist untouched." number 1
	end if
	-- Indices must be strictly descending and in range, or a
	-- deletion would shift a position still to delete.
	set prevIndex to (count of backupIDs) + 1
	repeat with idx in deleteIndices
		set idxVal to contents of idx
		if idxVal < 1 or idxVal > (count of backupIDs) then
			error "dedupe-in-place: delete index out of range: " & idxVal & " (playlist holds " & (count of backupIDs) & " songs); playlist untouched." number 1
		end if
		if idxVal ≥ prevIndex then
			error "dedupe-in-place: delete indices must be strictly descending; playlist untouched." number 1
		end if
		set prevIndex to idxVal
	end repeat

	-- Delete only the duplicate entries, highest first.
	-- A failed single deletion is not fatal here: the
	-- presence verification below is the judge, and a
	-- failure there triggers the snapshot restore.
	set deleteErrors to 0
	repeat with idx in deleteIndices
		set idxVal to contents of idx
		try
			with timeout of 3600 seconds
				tell application "Music"
					set songTracks to every track of destPl whose media kind is song
					delete item idxVal of songTracks
				end tell
			end timeout
		on error
			set deleteErrors to deleteErrors + 1
		end try
	end repeat

	-- Presence verification: exact count, every desired song
	-- present. Order is deliberately not checked.
	set verified to false
	try
		set verified to my verifyPresence(destPl, orderIDs)
	on error
		set verified to false
	end try
	if verified then
		return "DEDUPE OK: removed " & (count of deleteIndices) & " duplicate entries from \"" & playlistName & "\" in place (0 rebuilds); playlist now holds " & (count of orderIDs) & " unique songs."
	end if

	-- Verification failed: restore from the snapshot, trying
	-- both mappings, each verified exactly. Only a restore
	-- failure under both mappings is CRITICAL.
	set restoreResult to my tryRestoreBothMappings(destPl, backupIDs, "forward")
	if ok of restoreResult then
		if deleteErrors > 0 then
			error "dedupe-in-place: " & deleteErrors & " deletion(s) failed and verification failed; playlist restored from backup at " & backupPath & ", nothing applied." number 1
		else
			error "dedupe-in-place: verification failed (final song set does not match the desired set); playlist restored from backup at " & backupPath & "." number 1
		end if
	else
		error "dedupe-in-place: CRITICAL: verification failed AND restore failed under both mappings for \"" & playlistName & "\"; playlist may be partial. Re-run undo.applescript with backup " & backupPath & "." number 1
	end if
end run

on resolvePlaylist(playlistName, allowCreate)
	tell application "Music"
		set matches to every playlist whose name is playlistName
	end tell
	if (count of matches) is 0 then
		error "No playlist named \"" & playlistName & "\"." number 1
	else if (count of matches) > 1 then
		error "Refusing: " & (count of matches) & " playlists are named \"" & playlistName & "\"; refusing to guess which one you mean. Rename one of them and re-run." number 1
	else
		return item 1 of matches
	end if
end resolvePlaylist

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
	try
		with timeout of 3600 seconds
			tell application "Music"
				return persistent ID of every track of pl whose media kind is song
			end tell
		end timeout
	on error
		if my playlistTrackCount(pl) is 0 then return {}
		error "dedupe-in-place: could not read the playlist's song IDs (bulk read failed and the playlist is not empty); playlist untouched." number 1
	end try
end playlistIDs

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

on verifyPresence(pl, expectedIDs)
	set actualIDs to my playlistIDs(pl)
	if (count of actualIDs) is not (count of expectedIDs) then return false
	repeat with expectedID in expectedIDs
		if not (actualIDs contains (contents of expectedID)) then return false
	end repeat
	return true
end verifyPresence

on reverseList(a)
	set outList to {}
	repeat with i from (count of a) to 1 by -1
		set end of outList to item i of a
	end repeat
	return outList
end reverseList

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
			set remaining to my playlistTrackCount(pl)
		end try
		if remaining is 0 then return true
	end repeat
	return false
end deletePlaylistSongs

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

on tryRestoreMapping(pl, snapshotIDs, buildMapping)
	try
		my assertUserPlaylist(pl)
	on error errMsg
		return {ok:false, failed:{}}
	end try
	return my buildAndVerifyMapping(pl, snapshotIDs, buildMapping)
end tryRestoreMapping

on oppositeMapping(buildMapping)
	if buildMapping is "reversed" then return "forward"
	return "reversed"
end oppositeMapping

on tryRestoreBothMappings(pl, snapshotIDs, buildMapping)
	set firstResult to my tryRestoreMapping(pl, snapshotIDs, buildMapping)
	if ok of firstResult then return firstResult
	set otherMapping to my oppositeMapping(buildMapping)
	return my tryRestoreMapping(pl, snapshotIDs, otherMapping)
end tryRestoreBothMappings

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

on readIDFileStrict(filePath)
	try
		set raw to do shell script "cat " & quoted form of filePath
	on error errMsg
		error "dedupe-in-place: cannot read file " & filePath & ": " & errMsg number 1
	end try
	if raw is "" then return {}
	set AppleScript's text item delimiters to linefeed
	set linesList to paragraphs of raw
	set AppleScript's text item delimiters to ""
	set ids to {}
	repeat with ln in linesList
		set t to my trimText(contents of ln)
		if t is "" then
			error "dedupe-in-place: blank line in file " & filePath & ": refusing, the file may be truncated or corrupt." number 1
		end if
		if (t contains " ") or (t contains (character id 9)) or (t contains (character id 13)) then
			error "dedupe-in-place: malformed ID in file " & filePath & ": " & t number 1
		end if
		set end of ids to t
	end repeat
	return ids
end readIDFileStrict

on readIndicesFile(filePath)
	set rawLines to my readIDFileStrict(filePath)
	set indices to {}
	repeat with ln in rawLines
		set t to contents of ln
		try
			set idxVal to t as integer
		on error
			error "dedupe-in-place: malformed delete index (not an integer): " & t number 1
		end try
		-- Reject non-canonical integers ("1.5", "01", "+3"):
		-- re-rendering must give back the same text.
		if (idxVal as text) is not t then
			error "dedupe-in-place: malformed delete index (not a plain integer): " & t number 1
		end if
		set end of indices to idxVal
	end repeat
	return indices
end readIndicesFile

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
		error "dedupe-in-place: could not write file " & filePath & ": " & errMsg number errNum
	end try
end writeIDFile

on writeBackupAtomically(backupPath, idList)
	set tmpPath to backupPath & ".tmp"
	my writeIDFile(tmpPath, idList)
	try
		do shell script "mv -f " & quoted form of tmpPath & " " & quoted form of backupPath
	on error errMsg
		try
			do shell script "rm -f " & quoted form of tmpPath
		end try
		error "dedupe-in-place: could not install backup file " & backupPath & " (nothing was changed): " & errMsg number 1
	end try
	set checkIDs to my readIDFileStrict(backupPath)
	if not my listsEqual(checkIDs, idList) then
		error "dedupe-in-place: backup verification failed for " & backupPath & " (re-read does not match the playlist snapshot); nothing was changed." number 1
	end if
end writeBackupAtomically
