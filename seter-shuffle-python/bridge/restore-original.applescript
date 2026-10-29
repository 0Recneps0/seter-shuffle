-- restore-original.applescript: ONE-OFF RECOVERY, not part of the normal shuffle flow.
--
-- Restores a playlist to the order in a backup file. This script was
-- first written the night of the 2026-10-28 failure, when duplicating
-- tracks into a playlist landed them in reverse order on that Mac
-- and the .4 apply/undo loop kept failing verification. It originally
-- "fixed" that by flipping the duplicate order whenever its own
-- check came out backwards. That guessing is now REMOVED from the
-- default path, and this header explains why, because the flip is
-- actively dangerous under one of the two mechanisms behind the
-- failure:
--
--   * If duplicating inserts at the top (insert-reversed), a flip
--     is correct: duplicating reversed lands forwards.
--   * If duplicating appends normally but the every-track read is
--     reversed (read-reversed), a playlist that is ALREADY correct
--     on screen reads backwards, so the old flip logic rebuilds it
--     in reverse order and then declares success on a playlist it
--     just broke. The backup files from 2026-10-28 cannot tell
--     these two apart, so a flip must never be the default.
--
-- Default path (mode "auto", or an explicit probed mode): the script
-- first runs the same probe as bridge/probe-order.applescript on a
-- 3-song probe playlist it creates and deletes itself, and then
-- builds and verifies with the probed mode's formulas (see
-- buildForRestore / expectedForRestore, which mirror
-- seter_shuffle/order_direction.py). An ambiguous probe aborts with
-- the real playlist untouched. There is no flip in this path.
--
-- Explicit "flip" mode: the old assess-and-flip behaviour, kept ONLY
-- as a last resort for a throwaway playlist when the probe is
-- unavailable (for example, a library with fewer than 3 songs, or a
-- Music version that does not expose the track `index` property).
-- It is documented here as unsafe for a real playlist under
-- read-reversed, and it must never be used on one. If you are
-- reading this because someone told you to run "flip" on a real
-- playlist, stop and run the probe path instead.
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
--   osascript restore-original.applescript <playlist-name> <backup-txt> [mode] [snapshot-txt]
-- mode: "auto" (default: probe first), "forward",
--   "insert-reversed", "read-reversed", or "flip" (throwaway-only
--   last resort, see above). The snapshot path defaults to
--   <backup-txt>.fix-snapshot.
-- This takes a few minutes for 800 songs. Do not touch Music while
-- it runs. The final line says FIX OK or FIX FAILED.
--
-- UNVERIFIED ON A MAC (see BRIDGE-SAFETY.md): every Music
-- interaction here, including the probe's `index` property read.
-- Treat this as reviewed, not tested, until the Mac verification
-- procedure in BRIDGE-SAFETY.md has been run, starting with the probe.

on run argv
	if (count of argv) < 2 then
		error "fix: usage: <playlist-name> <backup-txt> [mode] [snapshot-txt]" number 1
	end if
	set playlistName to item 1 of argv
	set backupPath to item 2 of argv
	set modeText to "auto"
	if (count of argv) > 2 then set modeText to item 3 of argv
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
	if modeText is "flip" then
		return my runFlipMode(destPl, backupIDs, currentIDs, playlistName, backupPath, snapshotPath)
	end if
	set orderMode to missing value
	if modeText is "auto" then
		set orderMode to my probeMode()
	else
		set orderMode to my parseMode(modeText)
	end if
	-- Already exactly right under the probed mode: change nothing.
	if my verifyAgainst(destPl, my expectedForRestore(backupIDs, orderMode)) then
		return "FIX OK: playlist \"" & playlistName & "\" already matches the backup under mode " & orderMode & " (" & (count of backupIDs) & " songs). Nothing was changed. Snapshot saved at " & snapshotPath & "."
	end if
	set failed to my rebuild(destPl, my buildForRestore(backupIDs, orderMode))
	if (count of failed) is 0 and my verifyAgainst(destPl, my expectedForRestore(backupIDs, orderMode)) then
		return "FIX OK: restored \"" & playlistName & "\" to the backup order (" & (count of backupIDs) & " songs, mode " & orderMode & "). Snapshot of the pre-fix state saved at " & snapshotPath & "."
	end if
	-- Could not prove the restore. Put the snapshot back, then
	-- report failure honestly; never claim success on an unproven
	-- playlist, and never silently flip (see the header).
	set snapFailed to my rebuild(destPl, my buildForRestore(currentIDs, orderMode))
	if (count of snapFailed) is 0 and my verifyAgainst(destPl, my expectedForRestore(currentIDs, orderMode)) then
		error "FIX FAILED: could not restore \"" & playlistName & "\" to the backup order (mode " & orderMode & "), so the playlist was put back to its pre-fix state. Original backup: " & backupPath & ". Pre-fix snapshot: " & snapshotPath & ". Nothing was lost from the library." number 1
	end if
	error "FIX FAILED CRITICAL: could not restore \"" & playlistName & "\" to the backup order (mode " & orderMode & "), AND the pre-fix snapshot could not be put back either. Playlist may be partial. Original backup: " & backupPath & ". Pre-fix snapshot: " & snapshotPath & ". Keep both files and report this message; do not run the old undo again." number 1
end run

-- The old assess-and-flip flow, kept ONLY for explicit "flip" mode
-- (throwaway playlists, probe unavailable). See the header for why
-- this must never run on a real playlist: under read-reversed it
-- rebuilds an already-correct playlist in reverse order and calls
-- that a success.
on runFlipMode(destPl, backupIDs, currentIDs, playlistName, backupPath, snapshotPath)
	set state to my assess(destPl, backupIDs)
	if state is "good" then
		return "FIX OK (flip mode): playlist \"" & playlistName & "\" already matches the backup (" & (count of backupIDs) & " songs, exact order). Nothing was changed. Snapshot saved at " & snapshotPath & "."
	else if state is "display-ok" then
		return "FIX OK (flip mode): playlist \"" & playlistName & "\" is already in backup order as Music shows it (" & (count of backupIDs) & " songs). Nothing was changed. Snapshot saved at " & snapshotPath & "."
	end if
	set failed to my rebuild(destPl, backupIDs)
	if (count of failed) is 0 then
		set state to my assess(destPl, backupIDs)
		if state is "good" or state is "display-ok" then
			return "FIX OK (flip mode): restored \"" & playlistName & "\" to the backup order (" & (count of backupIDs) & " songs). Snapshot of the pre-fix state saved at " & snapshotPath & "."
		else if state is "flip" then
			set failed2 to my rebuild(destPl, my reverseList(backupIDs))
			if (count of failed2) is 0 then
				set state2 to my assess(destPl, backupIDs)
				if state2 is "good" or state2 is "display-ok" then
					return "FIX OK (flip mode): restored \"" & playlistName & "\" to the backup order (" & (count of backupIDs) & " songs). Music inserted the first build backwards, so the fix rebuilt it in reverse order, which landed forwards. Snapshot of the pre-fix state saved at " & snapshotPath & "."
				end if
			end if
		end if
	end if
	set snapFailed to my rebuild(destPl, currentIDs)
	if (count of snapFailed) is 0 then
		set snapState to my assess(destPl, currentIDs)
		if snapState is "flip" then
			set snapFailed2 to my rebuild(destPl, my reverseList(currentIDs))
			if (count of snapFailed2) is 0 then
				set snapState to my assess(destPl, currentIDs)
			end if
		end if
		if snapState is "good" or snapState is "display-ok" then
			error "FIX FAILED (flip mode): could not restore \"" & playlistName & "\" to the backup order, so the playlist was put back to its pre-fix state. Original backup: " & backupPath & ". Pre-fix snapshot: " & snapshotPath & ". Nothing was lost from the library." number 1
		end if
	end if
	error "FIX FAILED CRITICAL (flip mode): could not restore \"" & playlistName & "\" to the backup order, AND the pre-fix snapshot could not be put back either. Playlist may be partial. Original backup: " & backupPath & ". Pre-fix snapshot: " & snapshotPath & ". Keep both files and report this message." number 1
end runFlipMode

-- Run the probe in-process (same logic as probe-order.applescript):
-- create a 3-song probe playlist, read it back by list, by index,
-- and by position, decide a mode, delete the probe playlist. An
-- ambiguous result errors here, before the real playlist is touched.
-- The positional read travels through the same scripting bridge as
-- the list read, so it is a contradiction check only, never the sole
-- basis for a direction (see probe-order.applescript's header).
on probeMode()
	set probeName to "SeTeR Shuffle Probe (restore)"
	tell application "Music"
		set matches to every playlist whose name is probeName
	end tell
	if (count of matches) > 0 then
		error "fix: probe: refusing: a playlist named \"" & probeName & "\" already exists; delete or rename it and re-run." number 1
	end if
	set probePl to missing value
	try
		tell application "Music"
			set libSongs to every track of library playlist 1 whose media kind is song
		end tell
		if (count of libSongs) < 3 then
			error "fix: probe: library has fewer than 3 songs; cannot probe playlist order." number 1
		end if
		set pickedTracks to {item 1 of libSongs, item 2 of libSongs, item 3 of libSongs}
		set pickedIDs to {}
		tell application "Music"
			repeat with t in pickedTracks
				set end of pickedIDs to persistent ID of (contents of t)
			end repeat
		end tell
		if (item 1 of pickedIDs) is (item 2 of pickedIDs) or (item 1 of pickedIDs) is (item 3 of pickedIDs) or (item 2 of pickedIDs) is (item 3 of pickedIDs) then
			error "fix: probe: first 3 library songs are not distinct; cannot probe." number 1
		end if
		tell application "Music"
			set probePl to make new user playlist with properties {name:probeName}
		end tell
		tell application "Music"
			repeat with t in pickedTracks
				duplicate (contents of t) to probePl
			end repeat
		end tell
		set listIDs to my playlistIDs(probePl)
		set indexOrder to my probeIndexOrderFor(probePl, pickedIDs)
		set posEnds to my probePositionalEnds(probePl)
		set verdict to my probeVerdictFor(pickedIDs, listIDs, indexOrder, posEnds)
		try
			tell application "Music"
				delete probePl
			end tell
		on error
			error "fix: probe: probe playlist \"" & probeName & "\" could not be deleted after probing; delete it in Music, then re-run. Nothing else was changed." number 1
		end try
		if verdict is "ambiguous" then
			error "fix: probe: ambiguous result (list/index/positional reads do not fit any known model, or a read failed); refusing to build with a guessed direction. Delete nothing; report the probe lines." number 1
		end if
		return verdict
	on error errMsg number errNum
		if probePl is not missing value then
			try
				tell application "Music"
					delete probePl
				end tell
			end try
		end if
		error errMsg number errNum
	end try
end probeMode

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

on parseMode(modeText)
	if modeText is "forward" or modeText is "insert-reversed" or modeText is "read-reversed" then
		return modeText
	end if
	error "fix: unknown order mode \"" & modeText & "\" (expected auto, forward, insert-reversed, read-reversed, or flip)." number 1
end parseMode

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

-- Mirror of seter_shuffle/order_direction.py.
on buildForApply(orderIDs, orderMode)
	if orderMode is "insert-reversed" then return my reverseList(orderIDs)
	return orderIDs
end buildForApply

on expectedForApply(orderIDs, orderMode)
	if orderMode is "read-reversed" then return my reverseList(orderIDs)
	return orderIDs
end expectedForApply

on buildForRestore(snapshotIDs, orderMode)
	if orderMode is "forward" then return snapshotIDs
	return my reverseList(snapshotIDs)
end buildForRestore

on expectedForRestore(snapshotIDs, orderMode)
	return snapshotIDs
end expectedForRestore

on verifyAgainst(pl, expectedIDs)
	set actualIDs to my playlistIDs(pl)
	return my listsEqual(actualIDs, expectedIDs)
end verifyAgainst

-- Positional ends for the flip-mode assess path (general playlist;
-- unreliable when the playlist holds non-song entries).
on positionalEnds(pl)
	tell application "Music"
		set totalTracks to count of tracks of pl
		set songCount to count of (every track of pl whose media kind is song)
		if totalTracks is not songCount then return {firstID:"", lastID:"", reliable:false}
		if songCount is 0 then return {firstID:"", lastID:"", reliable:true}
		set firstID to persistent ID of track 1 of pl
		set lastID to persistent ID of track songCount of pl
	end tell
	return {firstID:firstID, lastID:lastID, reliable:true}
end positionalEnds

-- Flip-mode assess only. See the header: this logic is unsafe under
-- read-reversed, which is why it survives only in explicit "flip" mode.
on assess(pl, expectedIDs)
	set actual to my playlistIDs(pl)
	set revExpected to my reverseList(expectedIDs)
	set listGood to my listsEqual(actual, expectedIDs)
	set listReversed to my listsEqual(actual, revExpected)
	set ends to my positionalEnds(pl)
	if not (reliable of ends) then
		if listGood then return "good"
		if listReversed then return "flip"
		return "other"
	end if
	if (count of expectedIDs) is 0 then
		if (count of actual) is 0 then return "good"
		return "other"
	end if
	set posGood to ((firstID of ends) is item 1 of expectedIDs) and ((lastID of ends) is item -1 of expectedIDs)
	set posReversed to ((firstID of ends) is item -1 of expectedIDs) and ((lastID of ends) is item 1 of expectedIDs)
	if listGood and posGood then return "good"
	if listReversed and posGood then return "display-ok"
	if posReversed then return "flip"
	return "other"
end assess

-- Probe helpers (same logic as probe-order.applescript).
on probeIndexOrderFor(pl, pickedIDs)
	set n to count of pickedIDs
	set byIndex to {}
	repeat n times
		set end of byIndex to missing value
	end repeat
	repeat with pid in pickedIDs
		set pidStr to contents of pid
		set idx to missing value
		try
			tell application "Music"
				set idx to index of (first track of pl whose persistent ID is pidStr)
			end tell
		on error
			return missing value
		end try
		if idx is missing value then return missing value
		if idx < 1 or idx > n then return missing value
		if (item idx of byIndex) is not missing value then return missing value
		set item idx of byIndex to pidStr
	end repeat
	repeat with v in byIndex
		if (contents of v) is missing value then return missing value
	end repeat
	return byIndex
end probeIndexOrderFor

on probePositionalEnds(pl)
	tell application "Music"
		set totalTracks to count of tracks of pl
		set songCount to count of (every track of pl whose media kind is song)
		if totalTracks is not songCount then return missing value
		if songCount is not 3 then return missing value
		set firstID to persistent ID of track 1 of pl
		set lastID to persistent ID of track 3 of pl
	end tell
	return {firstID:firstID, lastID:lastID}
end probePositionalEnds

on probeVerdictFor(pickedIDs, listIDs, indexOrder, posEnds)
	if indexOrder is missing value then return "ambiguous"
	if posEnds is missing value then return "ambiguous"
	set revPicked to my reverseList(pickedIDs)
	set listForward to my listsEqual(listIDs, pickedIDs)
	set listReversed to my listsEqual(listIDs, revPicked)
	set indexForward to my listsEqual(indexOrder, pickedIDs)
	set indexReversed to my listsEqual(indexOrder, revPicked)
	set posForward to ((firstID of posEnds) is item 1 of pickedIDs) and ((lastID of posEnds) is item 3 of pickedIDs)
	set posReversed to ((firstID of posEnds) is item 3 of pickedIDs) and ((lastID of posEnds) is item 1 of pickedIDs)
	if listForward and indexForward and posForward then return "forward"
	if listReversed and indexReversed and posReversed then return "insert-reversed"
	if listReversed and indexForward and posForward then return "read-reversed"
	return "ambiguous"
end probeVerdictFor

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
