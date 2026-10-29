-- apply-order.applescript (SeTeR Shuffle, Python experimental core)
--
-- Applies an ordered persistent-ID list to a named playlist, with the
-- same safety idea as stable v2.6: snapshot BEFORE any change, verify
-- after, restore from the snapshot on ANY failure, and only touch a
-- regular user playlist (never a smart playlist, never the Library).
--
-- Usage:
--   osascript apply-order.applescript <playlist-name> <order-txt> <backup-txt>
-- order-txt: one persistent ID per line (written by the Python CLI
--   with --order-txt). backup-txt: where the pre-change IDs are saved,
--   one per line; undo.applescript reads the same file.
--
-- Order of operations (the backup write is deliberately first):
--   1. Resolve or create the playlist, assert it is a regular playlist.
--   2. Snapshot its current IDs to backup-txt. If that write fails,
--      NOTHING is changed.
--   3. Record the library size. Delete the playlist's songs, re-add
--      them in order from the library by persistent ID.
--   4. Verify: final song count equals the wanted count AND every
--      wanted ID is present. Also fail if the library shrank.
--   5. On any failure, restore from the backup IDs and exit non-zero.
--
-- UNVERIFIED ON A MAC (see README-PYTHON.md): every Music interaction
-- here, including `first track ... whose persistent ID is ...`,
-- duplicate-to-playlist ordering, and the verify/restore paths. The
-- Python core was tested here; this script was not, because this
-- machine has no Music app or osascript.

on run argv
	if (count of argv) < 3 then
		error "apply-order.applescript: usage: <playlist-name> <order-txt> <backup-txt>" number 1
	end if
	set playlistName to item 1 of argv
	set orderPath to item 2 of argv
	set backupPath to item 3 of argv

	set orderIDs to my readIDFile(orderPath)
	set wanted to count of orderIDs

	tell application "Music"
		if exists playlist playlistName then
			set destPl to playlist playlistName
		else
			set destPl to make new user playlist with properties {name:playlistName}
		end if
	end tell
	my assertUserPlaylist(destPl)

	-- 1. Snapshot BEFORE any change. A failed backup aborts everything.
	set backupIDs to my playlistIDs(destPl)
	my writeIDFile(backupPath, backupIDs)

	set libBefore to my librarySize()

	-- 2. Build: delete, then re-add in order from the library.
	tell application "Music"
		delete (every track of destPl whose media kind is song)
		repeat with pid in orderIDs
			set pidStr to contents of pid
			try
				set sourceTrack to (first track of library playlist 1 whose persistent ID is pidStr)
				duplicate sourceTrack to destPl
			on error
				-- Counted by the verify step below; do not abort mid-build
				-- or the playlist would be left half-built with no restore.
			end try
		end repeat
	end tell

	-- 3. Verify, restoring on any failure.
	set ok to my verifyIDs(destPl, wanted, orderIDs)
	set libAfter to my librarySize()
	if ok and libAfter < libBefore then
		set ok to false
	end if
	if not ok then
		my restoreIDs(destPl, backupIDs)
		error "apply-order: build or verify failed for \"" & playlistName & "\"; playlist restored from backup." number 1
	end if
	return "applied " & wanted & " songs to \"" & playlistName & "\" (backup: " & (count of backupIDs) & " songs)"
end run

on assertUserPlaylist(pl)
	set ok to false
	set plName to "(unknown)"
	tell application "Music"
		try
			set plName to name of pl
		end try
		try
			if (class of pl) is user playlist then
				if not (smart of pl) then set ok to true
			end if
		end try
	end tell
	if not ok then error "Refusing to modify \"" & plName & "\": it isn't a regular playlist, and changing it could remove songs from your library."
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

on verifyIDs(pl, expectedCount, expectedIDs)
	set actualIDs to my playlistIDs(pl)
	if (count of actualIDs) is not expectedCount then return false
	repeat with expectedID in expectedIDs
		if not (actualIDs contains (contents of expectedID)) then return false
	end repeat
	return true
end verifyIDs

on restoreIDs(pl, idList)
	my assertUserPlaylist(pl)
	tell application "Music"
		delete (every track of pl whose media kind is song)
		repeat with pid in idList
			set pidStr to contents of pid
			try
				set sourceTrack to (first track of library playlist 1 whose persistent ID is pidStr)
				duplicate sourceTrack to pl
			end try
		end repeat
	end tell
end restoreIDs

on readIDFile(filePath)
	try
		set raw to do shell script "cat " & quoted form of filePath
	on error errMsg
		error "apply-order: cannot read order file " & filePath & ": " & errMsg number 1
	end try
	set AppleScript's text item delimiters to linefeed
	set linesList to paragraphs of raw
	set AppleScript's text item delimiters to ""
	set ids to {}
	repeat with ln in linesList
		set t to contents of ln
		if t is not "" then set end of ids to t
	end repeat
	return ids
end readIDFile

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
		error "apply-order: could not write backup file, nothing was changed: " & errMsg number errNum
	end try
end writeIDFile
