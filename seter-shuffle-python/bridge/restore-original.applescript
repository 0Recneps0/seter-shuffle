-- restore-original.applescript: ONE-OFF RECOVERY, not part of the normal shuffle flow.
--
-- Restores a playlist to the order in a backup file, under a build
-- mapping measured on a sort-matched throwaway (see
-- bridge/sort-probe.applescript and seter_shuffle/order_direction.py's
-- mapping section). It takes NO probe and NO flip mode anymore:
--
--   * The 2026-10-28 probe (fresh 3-song playlist, "forward") did
--     not predict the real playlist, whose sort is Playlist Order
--     descending. A fresh playlist's direction says nothing about
--     a sorted target, so probing is not a fallback here either.
--   * The old flip logic is REMOVED, not merely demoted: under a
--     read/display split it rebuilt an already-correct playlist
--     in reverse order and called that a success, and the 2026-10-29
--     diagnostic (list read reversed against the backup while the
--     list's first track carries index 1) killed track index as a
--     manual-order reference, so no index-based assess path
--     survives here either.
--
-- Mapping (from run.sh's sort-probe, required as an argument):
-- "forward" means building X lands list read X; "reversed" means
-- building X lands list read reverse(X). To land list read D, this
-- script duplicates D under "forward" and reverse(D) under
-- "reversed", and verifies the list read against D, always. Any
-- other mapping string, or a missing one, aborts before any change.
-- A failed verify restores the pre-fix snapshot (under the same
-- mapping) and reports failure loudly; it never flips, never
-- guesses, and never claims success on an unproven playlist.
--
-- Safety, same contract as the other bridge scripts:
--  * Only a regular user playlist is ever modified, resolved by an
--    unambiguous filtered lookup, and checked again on every
--    rebuild. The Library itself and smart playlists are refused.
--  * Before anything changes, the playlist's CURRENT state is
--    snapshotted to a separate file, written atomically and
--    verified by re-reading it. If the restore cannot be proven,
--    the script puts the snapshot back and reports failure loudly
--    instead of claiming success.
--  * "Delete" here always means "remove a song entry from this
--    playlist". It never deletes a song from the library, and no
--    line in this file ever deletes from library playlist 1.
--  * Non-song entries are never deleted and are left in place.
--  * Build and restore loops run inside `with timeout of 3600
--    seconds` blocks, so a large playlist is not cut off by
--    AppleScript's default timeout mid-build.
--
-- Usage:
--   osascript restore-original.applescript <playlist-name> <backup-txt> <mapping> [snapshot-txt]
-- mapping: "forward" or "reversed" (required). The snapshot path
--   defaults to <backup-txt>.fix-snapshot.
-- This takes a few minutes for 800 songs. Do not touch Music while
-- it runs. The final line says FIX OK or FIX FAILED.
--
-- UNVERIFIED ON A MAC (see BRIDGE-SAFETY.md): every Music
-- interaction here. Treat this as reviewed, not tested, until the
-- Mac verification procedure in BRIDGE-SAFETY.md has been run,
-- starting with the sort-matched throwaway probe.

on run argv
	if (count of argv) < 3 then
		error "fix: usage: <playlist-name> <backup-txt> <mapping> [snapshot-txt] (mapping is required: forward or reversed from sort-probe on a sort-matched throwaway)" number 1
	end if
	set playlistName to item 1 of argv
	set backupPath to item 2 of argv
	set buildMapping to my parseMapping(item 3 of argv)
	set snapshotPath to backupPath & ".fix-snapshot"
	if (count of argv) > 3 then set snapshotPath to item 4 of argv
	if playlistName is "" then
		error "fix: playlist name must not be empty." number 1
	end if
	if snapshotPath is backupPath then
		error "fix: snapshot path must differ from the backup path." number 1
	end if
	set backupIDs to my readBackupFile(backupPath)
	set destPl to my resolvePlaylist(playlistName)
	my assertUserPlaylist(destPl)
	set currentIDs to my playlistIDs(destPl)
	my writeBackupAtomically(snapshotPath, currentIDs)
	-- Already exactly right: change nothing.
	if my verifyAgainst(destPl, backupIDs) then
		return "FIX OK: playlist \"" & playlistName & "\" already matches the backup (" & (count of backupIDs) & " songs). Nothing was changed. Snapshot saved at " & snapshotPath & "."
	end if
	set failed to my rebuild(destPl, my buildForMapping(backupIDs, buildMapping))
	if (count of failed) is 0 and my verifyAgainst(destPl, backupIDs) then
		return "FIX OK: restored \"" & playlistName & "\" to the backup order (" & (count of backupIDs) & " songs, mapping " & buildMapping & "). Snapshot of the pre-fix state saved at " & snapshotPath & "."
	end if
	-- Could not prove the restore. Put the snapshot back, then
	-- report failure honestly; never claim success on an unproven
	-- playlist, and never flip (see the header).
	set snapFailed to my rebuild(destPl, my buildForMapping(currentIDs, buildMapping))
	if (count of snapFailed) is 0 and my verifyAgainst(destPl, currentIDs) then
		error "FIX FAILED: could not restore \"" & playlistName & "\" to the backup order (mapping " & buildMapping & "), so the playlist was put back to its pre-fix state. Original backup: " & backupPath & ". Pre-fix snapshot: " & snapshotPath & ". Nothing was lost from the library." number 1
	end if
	error "FIX FAILED CRITICAL: could not restore \"" & playlistName & "\" to the backup order (mapping " & buildMapping & "), AND the pre-fix snapshot could not be put back either. Playlist may be partial. Original backup: " & backupPath & ". Pre-fix snapshot: " & snapshotPath & ". Keep both files and report this message; do not run the old undo again." number 1
end run

-- The build mapping, validated, never defaulted.
on parseMapping(mappingText)
	if mappingText is "forward" or mappingText is "reversed" then
		return mappingText
	end if
	error "fix: unknown or missing build mapping \"" & mappingText & "\" (expected forward or reversed from sort-probe on a sort-matched throwaway)." number 1
end parseMapping

-- Mirror of seter_shuffle/order_direction.py's mapping section.
on buildForMapping(desiredIDs, buildMapping)
	if buildMapping is "reversed" then return my reverseList(desiredIDs)
	return desiredIDs
end buildForMapping

on resolvePlaylist(playlistName)
	tell application "Music"
		set matches to every playlist whose name is playlistName
	end tell
	if (count of matches) is 0 then
		error "fix: no playlist named \"" & playlistName & "\"." number 1
	else if (count of matches) > 1 then
		error "fix: refusing: " & (count of matches) & " playlists are named \"" & playlistName & "\"; refusing to guess which one you mean. Rename one of them and re-run." number 1
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
	if not ok then error "fix: refusing to modify \"" & plName & "\": it isn't a regular user playlist (or it is the Library itself)."
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

on reverseList(a)
	set outList to {}
	repeat with i from (count of a) to 1 by -1
		set end of outList to item i of a
	end repeat
	return outList
end reverseList

on verifyAgainst(pl, expectedIDs)
	set actualIDs to my playlistIDs(pl)
	return my listsEqual(actualIDs, expectedIDs)
end verifyAgainst

-- Delete the playlist's songs and duplicate the given IDs into it,
-- in the given order. Returns the IDs that could not be found in
-- the library (empty means every song was placed). Never throws
-- for a missing song; the caller decides what a failure means.
on rebuild(pl, idList)
	set failedIDs to {}
	try
		my assertUserPlaylist(pl)
	on error
		return {"assert-failed"}
	end try
	try
		with timeout of 3600 seconds
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
		end timeout
	on error
		set end of failedIDs to "rebuild-error"
	end try
	return failedIDs
end rebuild

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

on readBackupFile(filePath)
	try
		set raw to do shell script "cat " & quoted form of filePath
	on error errMsg
		error "fix: cannot read backup file " & filePath & ": " & errMsg number 1
	end try
	if raw is "" then return {}
	set AppleScript's text item delimiters to linefeed
	set linesList to paragraphs of raw
	set AppleScript's text item delimiters to ""
	set ids to {}
	repeat with ln in linesList
		set t to my trimText(contents of ln)
		if t is "" then
			error "fix: blank line in backup file " & filePath & ": refusing, the file may be truncated or corrupt." number 1
		end if
		if (t contains " ") or (t contains (character id 9)) or (t contains (character id 13)) then
			error "fix: malformed ID in backup file " & filePath & ": " & t number 1
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
		error "fix: could not write file " & filePath & ": " & errMsg number errNum
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
		error "fix: could not install snapshot file " & backupPath & " (nothing was changed): " & errMsg number 1
	end try
	set checkIDs to my readBackupFile(backupPath)
	if not my listsEqual(checkIDs, idList) then
		error "fix: snapshot verification failed for " & backupPath & " (re-read does not match); nothing was changed." number 1
	end if
end writeBackupAtomically
