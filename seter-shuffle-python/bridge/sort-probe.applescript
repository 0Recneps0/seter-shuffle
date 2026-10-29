-- sort-probe.applescript (SeTeR Shuffle, Python experimental core)
--
-- Measures the end-to-end build-to-list mapping on a THROWAWAY
-- playlist that the user has set to the SAME sort as the target
-- playlist (for the 2026-10-28 failure, Playlist Order descending).
-- This is the ONLY direction authority for builds from 2026-10-29.
-- It replaces both earlier approaches, and the header explains why
-- each of them died, because reusing either one would repeat a
-- failure that already cost two real-playlist runs:
--
--   * Fresh-probe direction (.5): a fresh 3-song playlist reported
--     "forward" while the real sorted 806-song playlist still
--     failed every build. A fresh playlist does not share the
--     target's sort, so its direction says nothing about it.
--   * Track index as manual order (drafted, then discarded before
--     publication): a read-only diagnostic on the real playlist
--     showed its list read reversed against the original backup
--     while its first list track carries index 1. If index were
--     manual order and the list were sorted descending (reverse
--     of manual), that track would carry index 806, not 1. So
--     index either follows the current view (carrying no manual
--     information) or the manual order itself is now reverse(B).
--     Either way index cannot classify a sort, and it is never
--     used here except as a reported value nowhere in this script.
--
-- What this script does, in order, on the throwaway ONLY:
--  1. Resolves the throwaway by unambiguous name lookup (no
--     creation, no guessing: zero or multiple matches refuse).
--  2. Snapshots its current list-read order to the snapshot file
--     given as the 2nd argument, written atomically and verified
--     by re-reading it. A failed snapshot aborts with the
--     throwaway untouched.
--  3. Builds a ROTATION of the snapshot order (items 2..n plus
--     item 1). A rotation is chosen deliberately: for 5 or more
--     distinct songs it is neither the snapshot order nor its
--     reverse, so the read-back cannot be mistaken for either.
--     The throwaway must hold at least 5 songs with distinct IDs
--     for the test to be clean; fewer, or duplicates among the
--     first entries, refuse the run.
--  4. Reads the list back and classifies the mapping (mirroring
--     seter_shuffle/order_direction.py's mapping_from_build_result
--     exactly): "forward" if the read equals the build order,
--     "reversed" if it equals the exact reverse of the build
--     order, "other" otherwise (another sort, a partial build, or
--     any behaviour the bridge cannot predict).
--  5. Restores the throwaway to its snapshot order UNDER THE
--     MEASURED MAPPING (forward: duplicate the snapshot; reversed:
--     duplicate its reverse) and verifies the list read against
--     the snapshot. A failed restore is a hard error naming the
--     snapshot file, and the throwaway is left for the user to
--     inspect rather than silently left shuffled.
--
-- Output: a block of lines ending with either
--   MAPPING: forward
--   MAPPING: reversed
--   MAPPING: other
-- plus SORTPROBE_OK on success, or an error (non-zero exit) on any
-- failure. run.sh parses MAPPING and records it with the throwaway
-- name and a timestamp; builds refuse to run without a fresh
-- recorded mapping (24 hours), and the mapping is only valid while
-- the target's sort matches the throwaway's sort at probe time.
-- If the target's sort may have changed since the probe, re-probe.
--
-- This script never touches the Library, never creates a playlist,
-- and never modifies any playlist but the named throwaway. The
-- throwaway's own songs are never deleted from the library: delete
-- here removes playlist entries only, and the snapshot restore puts
-- them back.
--
-- UNVERIFIED ON A MAC (see BRIDGE-SAFETY.md): every Music
-- interaction here. Treat this as reviewed, not tested, until the
-- Mac procedure in BRIDGE-SAFETY.md has been run on throwaways.

on run argv
	if (count of argv) < 2 then
		error "sort-probe: usage: <throwaway-playlist-name> <snapshot-txt>" number 1
	end if
	set playlistName to item 1 of argv
	set snapshotPath to item 2 of argv
	if playlistName is "" then
		error "sort-probe: playlist name must not be empty." number 1
	end if
	set destPl to my resolvePlaylist(playlistName)
	my assertUserPlaylist(destPl)
	set snapshotIDs to my playlistIDs(destPl)
	set n to count of snapshotIDs
	if n < 5 then
		error "sort-probe: throwaway playlist \"" & playlistName & "\" holds only " & n & " song(s); the mapping test needs at least 5 songs with distinct IDs for a clean rotation. Add songs and re-run; throwaway untouched." number 1
	end if
	-- The rotation test needs distinct IDs: with a duplicate entry
	-- the read-back could match more than one mapping by accident.
	set seenIDs to {}
	repeat with pid in snapshotIDs
		set pidStr to contents of pid
		if pidStr is in seenIDs then
			error "sort-probe: throwaway playlist \"" & playlistName & "\" contains a duplicate song entry; the mapping test needs distinct IDs. Use a throwaway without duplicates and re-run; throwaway untouched." number 1
		end if
		set end of seenIDs to pidStr
	end repeat
	my writeBackupAtomically(snapshotPath, snapshotIDs)
	-- Rotation: items 2..n plus item 1. Neither the snapshot order
	-- nor its reverse (for n >= 5 distinct IDs), by construction.
	set buildIDs to {}
	repeat with i from 2 to n
		set end of buildIDs to item i of snapshotIDs
	end repeat
	set end of buildIDs to item 1 of snapshotIDs
	set failed to my rebuild(destPl, buildIDs)
	if (count of failed) > 0 then
		set snapFailed to my rebuild(destPl, snapshotIDs)
		error "sort-probe: build failed for \"" & playlistName & "\" (" & my joinList(failed) & " song(s) not found in the library); throwaway restore attempted, snapshot at " & snapshotPath & "; check the throwaway in Music before re-running." number 1
	end if
	set listAfter to my playlistIDs(destPl)
	set mapping to my mappingFromBuild(buildIDs, listAfter)
	-- Restore the throwaway under the measured mapping, and verify.
	-- An "other" mapping cannot restore reliably by formula, so it
	-- restores by duplicating the snapshot as-is and reports the
	-- outcome honestly: if that verify also fails, the throwaway is
	-- left (with its snapshot named) for inspection, not hidden.
	set restoreIDs to snapshotIDs
	if mapping is "reversed" then set restoreIDs to my reverseList(snapshotIDs)
	set snapFailed to my rebuild(destPl, restoreIDs)
	set restored to false
	if (count of snapFailed) is 0 then
		try
			set restored to my verifyAgainst(destPl, snapshotIDs)
		on error
			set restored to false
		end try
	end if
	if mapping is "other" then
		error "sort-probe: MAPPING: other (read-back after building the rotation matched neither the build order nor its reverse; the throwaway's sort or behaviour is not one the bridge can build into). Throwaway restored: " & restored & ". Snapshot at " & snapshotPath & ". Set the throwaway sort to Playlist Order (same as the target) and re-probe; do not build a real playlist on an 'other' mapping." number 1
	end if
	if not restored then
		error "sort-probe: MAPPING: " & mapping & " but the throwaway restore to its snapshot could not be verified; throwaway may still hold the rotation order. Snapshot at " & snapshotPath & "; restore it by hand or re-run sort-probe, and do not build a real playlist until the throwaway restores cleanly." number 1
	end if
	return "MAPPING: " & mapping & linefeed & "SORTPROBE_OK"
end run

on resolvePlaylist(playlistName)
	tell application "Music"
		set matches to every playlist whose name is playlistName
	end tell
	if (count of matches) is 0 then
		error "sort-probe: no playlist named \"" & playlistName & "\"." number 1
	else if (count of matches) > 1 then
		error "sort-probe: refusing: " & (count of matches) & " playlists are named \"" & playlistName & "\"; refusing to guess which one you mean. Rename one of them and re-run." number 1
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
	if not ok then error "sort-probe: refusing to modify \"" & plName & "\": it isn't a regular user playlist (or it is the Library itself)."
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

-- Mirror of seter_shuffle/order_direction.py's
-- mapping_from_build_result, exactly.
on mappingFromBuild(buildIDs, listAfter)
	if (count of buildIDs) is not (count of listAfter) then return "other"
	if my listsEqual(listAfter, buildIDs) then return "forward"
	if my listsEqual(listAfter, my reverseList(buildIDs)) then return "reversed"
	return "other"
end mappingFromBuild

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

on joinList(idList)
	set AppleScript's text item delimiters to ", "
	set t to idList as text
	set AppleScript's text item delimiters to ""
	if (count of t) > 500 then set t to (text 1 thru 500 of t) & "..."
	return t
end joinList

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
		error "sort-probe: cannot read file " & filePath & ": " & errMsg number 1
	end try
	if raw is "" then return {}
	set AppleScript's text item delimiters to linefeed
	set linesList to paragraphs of raw
	set AppleScript's text item delimiters to ""
	set ids to {}
	repeat with ln in linesList
		set t to my trimText(contents of ln)
		if t is "" then
			error "sort-probe: blank line in file " & filePath & ": refusing, the file may be truncated or corrupt." number 1
		end if
		if (t contains " ") or (t contains (character id 9)) or (t contains (character id 13)) then
			error "sort-probe: malformed ID in file " & filePath & ": " & t number 1
		end if
		set end of ids to t
	end repeat
	return ids
end readIDFileStrict

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
		error "sort-probe: could not write file " & filePath & ": " & errMsg number errNum
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
		error "sort-probe: could not install snapshot file " & backupPath & " (nothing was changed): " & errMsg number 1
	end try
	set checkIDs to my readIDFileStrict(backupPath)
	if not my listsEqual(checkIDs, idList) then
		error "sort-probe: snapshot verification failed for " & backupPath & " (re-read does not match the throwaway snapshot); nothing was changed." number 1
	end if
end writeBackupAtomically
