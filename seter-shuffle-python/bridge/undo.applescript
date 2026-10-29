-- undo.applescript (SeTeR Shuffle, Python experimental core)
--
-- Restores a playlist from a backup ID file written by
-- apply-order.applescript. Same guard as the apply script: only a
-- regular user playlist is ever touched.
--
-- Usage:
--   osascript undo.applescript <playlist-name> <backup-txt>
-- backup-txt: one persistent ID per line, in the original order.
-- An empty backup file restores an empty playlist, which is the
-- correct result for a playlist apply-order created from scratch
-- (for example, a first-run "SeTeR Flow").
--
-- If some backup IDs are no longer in the library, they are skipped
-- and the script exits non-zero with a summary, so a partial restore
-- is loud instead of silent.
--
-- UNVERIFIED ON A MAC (see README-PYTHON.md): every Music interaction
-- here. The Python core was tested here; this script was not, because
-- this machine has no Music app or osascript.

on run argv
	if (count of argv) < 2 then
		error "undo.applescript: usage: <playlist-name> <backup-txt>" number 1
	end if
	set playlistName to item 1 of argv
	set backupPath to item 2 of argv

	try
		set raw to do shell script "cat " & quoted form of backupPath
	on error errMsg
		error "undo: cannot read backup file " & backupPath & ": " & errMsg number 1
	end try
	set AppleScript's text item delimiters to linefeed
	set linesList to paragraphs of raw
	set AppleScript's text item delimiters to ""
	set backupIDs to {}
	repeat with ln in linesList
		set t to contents of ln
		if t is not "" then set end of backupIDs to t
	end repeat

	tell application "Music"
		if not (exists playlist playlistName) then
			error "undo: no playlist named \"" & playlistName & "\"" number 1
		end if
		set destPl to playlist playlistName
	end tell
	my assertUserPlaylist(destPl)

	set restoredCount to 0
	set failedCount to 0
	tell application "Music"
		delete (every track of destPl whose media kind is song)
		repeat with pid in backupIDs
			set pidStr to contents of pid
			try
				set sourceTrack to (first track of library playlist 1 whose persistent ID is pidStr)
				duplicate sourceTrack to destPl
				set restoredCount to restoredCount + 1
			on error
				set failedCount to failedCount + 1
			end try
		end repeat
	end tell
	if failedCount > 0 then
		error "undo: restored " & restoredCount & " of " & (count of backupIDs) & " songs to \"" & playlistName & "\"; " & failedCount & " song(s) were not found in the library." number 1
	end if
	return "restored " & restoredCount & " songs to \"" & playlistName & "\""
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
