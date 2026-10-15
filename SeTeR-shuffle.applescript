-- SeTeR Shuffle v2.3
-- True-random (Fisher-Yates) shuffle for Apple Music.
--
-- WHAT'S NEW IN v2.3
--   LIBRARY PROTECTION (songs must never vanish from your library):
--   * The script refuses to touch anything that isn't a regular user playlist
--     (deleting "tracks" from the Library itself would remove songs from your library).
--   * Library size is checked before/after every playlist rewrite; if it shrinks the
--     run stops with a loud error.
--   * Once a day, the daily run saves a manifest of your whole library (ID, artist,
--     album, title) to ~/Documents/SeTeRShuffle/backups/ (kept 14 days), so you
--     always have a list of what you owned.
--   NEW FEATURES:
--   * Undo last shuffle (interactive menu): puts a playlist back the way it was
--     before the last in-place shuffle/dedupe, from the backup file.
--   * Remove duplicates (interactive menu): cleans repeated songs out of any
--     playlist, keeping the original order.
--   * Library shuffle lets you pick a size (100 / 250 / 500 / 1000 / all).
--   * Rediscover now scales with your library: 1% of its songs (min 30, max 500),
--     so it grows as your library does. The percentage, min/max and the
--     "unplayed for" days are settings (properties below).
--   FROM v2.2: duplicate-safe verification, restore-on-any-failure, smarter
--   no-same-artist logic, in-place "SeTeR Shuffle" playlist, exit code on failure,
--   timestamped self-rotating log.
--
-- SAFETY: Every in-place change snapshots the playlist (song count + persistent
--   IDs) to ~/Library/Logs/seter-shuffle-backup.txt BEFORE making changes, then
--   verifies after: count must match and every expected ID must still be present.
--   If the build or verification fails, the playlist is restored from the backup
--   and the run aborts with an error logged.
--
-- INTERACTIVE (double-click the app): a menu offers Shuffle, Rediscover,
--   Remove duplicates, or Undo last shuffle.
--   Shuffle: whole library or one playlist. Library -> builds/refreshes the
--     "SeTeR Shuffle" playlist. Playlist -> shuffles that playlist itself in
--     place (name, artwork, description kept). Optional no-same-artist.
--   Rediscover: forgotten favorites (2+ plays, unplayed 60+ days) into
--     "SeTeR Rediscover", topped up with long-unplayed 1-play songs and
--     never-played old adds so it always fills up to its target size (1% of your
--     library, between 30 and 500 songs). Kept in place so its
--     cover artwork survives.
--
-- AUTOMATIC (daily): osascript SeTeR-shuffle.applescript daily "Playlist Name"
--   Backs up a library manifest (once a day), shuffles the named playlist in
--   place (removing duplicates) AND refreshes "SeTeR Rediscover", no dialogs.
--   Progress and errors go to ~/Library/Logs/seter-shuffle.log. See
--   com.seter.daily.plist for the scheduled job (daily at 8:00 AM).
--
-- INSTALL:
--   1. Save this file as ~/Documents/SeTeRShuffle/SeTeR-shuffle.applescript
--      (double-clicking it opens Script Editor).
--   2. Manual app: in Script Editor, File > Export > File Format: Application,
--      save as "SeTeR Shuffle" (e.g. in Applications).
--   3. Daily run: copy com.seter.daily.plist to ~/Library/LaunchAgents/
--      then run once in Terminal:
--        launchctl load ~/Library/LaunchAgents/com.seter.daily.plist
--   First run: allow control of the Music app when macOS asks.

-- SETTINGS (change these if you like)
property rediscoverPercent : 1 -- "SeTeR Rediscover" holds this % of your library...
property rediscoverMin : 30 -- ...but never fewer than this many songs
property rediscoverMax : 500 -- ...and never more than this many
property staleDays : 60 -- "forgotten" = not played / not added for this many days
property backupKeepDays : 14 -- how long library manifests are kept
property defaultDailyPlaylist : "my new sandwich recipe"

-- internal state
property isDaily : false
property hadError : false
property tempPlaylistName : "SeTeRShuffleTemp"

on run argv
	set isDaily to false
	set hadError to false
	if (count of argv) > 0 and (item 1 of argv) is "daily" then
		set isDaily to true
		set targetName to defaultDailyPlaylist
		if (count of argv) > 1 and (item 2 of argv) is not "" then set targetName to item 2 of argv
		try
			my backupLibraryManifest()
		on error errMsg
			-- A missing manifest is worth a warning, not a reason to skip the shuffle.
			my logLine("WARNING: library manifest backup failed: " & errMsg)
		end try
		try
			my doDailyShuffle(targetName)
		on error errMsg number errNum
			my reportError(errMsg, errNum)
		end try
		try
			my doDailyRediscover()
		on error errMsg number errNum
			my reportError(errMsg, errNum)
		end try
		-- Non-zero exit so launchd / Shuffle Sandwich can tell something failed.
		if hadError then error "SeTeR Shuffle daily run had errors. See ~/Library/Logs/seter-shuffle.log" number 1
	else
		try
			my doInteractive()
		on error errMsg number errNum
			my reportError(errMsg, errNum)
		end try
	end if
end run

on reportError(errMsg, errNum)
	if errNum is -128 then return -- user cancelled, stay quiet
	set hadError to true
	my logLine("ERROR: " & errMsg)
	if not isDaily then
		if (length of errMsg) > 400 then set errMsg to (text 1 thru 400 of errMsg) & "…"
		display dialog "SeTeR ran into a problem:" & return & return & errMsg buttons {"OK"} default button "OK" with icon caution
	end if
end reportError

-- Appends "YYYY-MM-DD HH:MM:SS <line>" to the log; rotates it at 1 MB.
-- Never throws: a logging problem must not break a shuffle.
on logLine(theLine)
	try
		set cmd to "f=\"$HOME/Library/Logs/seter-shuffle.log\"; mkdir -p \"$HOME/Library/Logs\"; "
		set cmd to cmd & "if [ -f \"$f\" ] && [ \"$(stat -f%z \"$f\")\" -gt 1048576 ]; then mv \"$f\" \"$f.1\"; fi; "
		set cmd to cmd & "printf '%s %s\\n' \"$(date '+%Y-%m-%d %H:%M:%S')\" " & quoted form of theLine & " >> \"$f\""
		do shell script cmd
	end try
end logLine

-- ---------------------------------------------------------------------------
-- LIBRARY PROTECTION
-- ---------------------------------------------------------------------------

-- Throws unless pl is a regular (non-smart) user playlist. Deleting tracks from
-- the Library playlist (or other special playlists) would remove songs from the
-- library itself, so every destructive path goes through this check first.
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

on safeText(x)
	if x is missing value then return ""
	return x as text
end safeText

-- Saves a tab-separated list of every track in the library (ID, artist, album,
-- title) to ~/Documents/SeTeRShuffle/backups/. One file per day; old ones pruned.
on backupLibraryManifest()
	set backupDir to (POSIX path of (path to documents folder)) & "SeTeRShuffle/backups"
	set dayStr to do shell script "date +%Y-%m-%d"
	set manifestPath to backupDir & "/library-manifest-" & dayStr & ".tsv"
	do shell script "mkdir -p " & quoted form of backupDir
	if (do shell script "test -f " & quoted form of manifestPath & " && echo yes || echo no") is "yes" then return
	tell application "Music"
		set pids to persistent ID of every track of library playlist 1
		set nms to name of every track of library playlist 1
		set arts to artist of every track of library playlist 1
		set albs to album of every track of library playlist 1
	end tell
	set total to count of pids
	set outLines to {"# SeTeR Shuffle library manifest " & dayStr & " (" & total & " tracks)"}
	repeat with i from 1 to total
		set end of outLines to (item i of pids) & tab & my safeText(item i of arts) & tab & my safeText(item i of albs) & tab & my safeText(item i of nms)
	end repeat
	set AppleScript's text item delimiters to linefeed
	set fileText to outLines as text
	set AppleScript's text item delimiters to ""
	set fh to open for access (POSIX file manifestPath) with write permission
	try
		set eof of fh to 0
		write fileText to fh as «class utf8»
		close access fh
	on error errMsg number errNum
		try
			close access fh
		end try
		error errMsg number errNum
	end try
	try
		do shell script "find " & quoted form of backupDir & " -name 'library-manifest-*.tsv' -mtime +" & backupKeepDays & " -delete"
	end try
	my logLine("library manifest saved (" & total & " tracks)")
end backupLibraryManifest

-- ---------------------------------------------------------------------------
-- SNAPSHOT / VERIFY / RESTORE
-- ---------------------------------------------------------------------------

-- SAFETY: Snapshot the playlist's persistent IDs to a backup file.
-- Called BEFORE any in-place change. Returns {count, idList} for the playlist
-- as it is right now (including any duplicates). The backup file
-- (~/Library/Logs/seter-shuffle-backup.txt) is overwritten each run.
-- Throws if the backup can't be written, so nothing is modified without a backup.
on snapshotPlaylist(destPl, playlistName)
	tell application "Music"
		set idList to persistent ID of every track of destPl whose media kind is song
	end tell
	set n to count of idList
	set logsDir to (POSIX path of (path to home folder)) & "Library/Logs"
	set backupPath to logsDir & "/seter-shuffle-backup.txt"
	set AppleScript's text item delimiters to linefeed
	set idText to idList as text
	set AppleScript's text item delimiters to ""
	set fileContent to "# SeTeR Shuffle Backup" & linefeed & "# Playlist: " & playlistName & linefeed & "# Date: " & my dateStamp() & linefeed & "# Count: " & n & linefeed & idText
	do shell script "mkdir -p " & quoted form of logsDir
	set fh to open for access (POSIX file backupPath) with write permission
	try
		set eof of fh to 0
		write fileContent to fh as «class utf8»
		close access fh
	on error errMsg number errNum
		try
			close access fh
		end try
		error "Couldn't write the backup file, nothing was changed: " & errMsg number errNum
	end try
	return {n, idList}
end snapshotPlaylist

-- SAFETY: Verify the playlist holds exactly the expected songs.
-- Count must match AND every expected persistent ID must be present.
on verifyPlaylist(destPl, expectedCount, expectedIDs, playlistName)
	tell application "Music"
		set actualIDs to persistent ID of every track of destPl whose media kind is song
	end tell
	set actualCount to count of actualIDs
	if actualCount is not expectedCount then
		my logLine("VERIFY FAILED for \"" & playlistName & "\": expected " & expectedCount & " songs, found " & actualCount)
		return false
	end if
	set missingCount to 0
	repeat with expectedID in expectedIDs
		-- "contains" runs natively; much faster than a nested AppleScript loop.
		if not (actualIDs contains (contents of expectedID)) then set missingCount to missingCount + 1
	end repeat
	if missingCount > 0 then
		my logLine("VERIFY FAILED for \"" & playlistName & "\": " & missingCount & " song(s) missing from playlist")
		return false
	end if
	my logLine("verified \"" & playlistName & "\" (" & actualCount & " songs, all accounted for)")
	return true
end verifyPlaylist

-- SAFETY: Restore the playlist from an ID list (original order).
-- Deletes current songs FROM THE PLAYLIST and re-adds each track by persistent
-- ID from the library. Returns how many were restored.
on restorePlaylistFromBackup(destPl, playlistName, idList)
	my assertUserPlaylist(destPl)
	set totalIDs to count of idList
	my logLine("RESTORING \"" & playlistName & "\" from backup (" & totalIDs & " songs)")
	set restoredCount to 0
	set failedCount to 0
	tell application "Music"
		delete (every track of destPl whose media kind is song)
		repeat with pid in idList
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
		my logLine("RESTORE WARNING for \"" & playlistName & "\": " & failedCount & " song(s) not found in library, could not restore")
	end if
	my logLine("restored \"" & playlistName & "\" (" & restoredCount & " of " & totalIDs & " songs)")
	return restoredCount
end restorePlaylistFromBackup

-- Rewrites an existing playlist's songs in the given order, with the safety net:
-- build -> verify -> restore from backup on ANY failure (build error or bad verify).
-- expectedCount/expectedIDs describe what the playlist should hold afterwards;
-- backupIDs is what to restore if things go wrong (the pre-change playlist).
-- Returns true on success, false if it had to restore.
on rewritePlaylistSafely(destPl, plName, finalTracks, expectedCount, expectedIDs, backupIDs)
	try
		my buildPlaylist(destPl, finalTracks, true)
	on error errMsg
		my logLine("BUILD FAILED for \"" & plName & "\": " & errMsg)
		my removeTempPlaylist()
		my restorePlaylistFromBackup(destPl, plName, backupIDs)
		return false
	end try
	if not (my verifyPlaylist(destPl, expectedCount, expectedIDs, plName)) then
		my restorePlaylistFromBackup(destPl, plName, backupIDs)
		return false
	end if
	return true
end rewritePlaylistSafely

on removeTempPlaylist()
	tell application "Music"
		try
			delete (every user playlist whose name is tempPlaylistName)
		end try
	end tell
end removeTempPlaylist

-- ---------------------------------------------------------------------------
-- INTERACTIVE MODES
-- ---------------------------------------------------------------------------

on doInteractive()
	set modeChoice to choose from list {"🔀 Shuffle", "💡 Rediscover", "🧹 Remove duplicates", "↩️ Undo last shuffle"} with prompt "What should SeTeR do?"
	if modeChoice is false then return
	set m to item 1 of modeChoice
	if m is "🔀 Shuffle" then
		my doShuffle()
	else if m is "💡 Rediscover" then
		my doRediscover()
	else if m is "🧹 Remove duplicates" then
		my doRemoveDuplicates()
	else
		my doUndo()
	end if
end doInteractive

-- Lists regular playlists and returns the chosen name, or missing value.
on choosePlaylistName(promptText)
	tell application "Music"
		set pNames to name of every user playlist whose smart is false
	end tell
	if (count of pNames) is 0 then
		display dialog "No regular playlists found in your library." buttons {"OK"} default button "OK"
		return missing value
	end if
	set pChoice to choose from list pNames with prompt promptText
	if pChoice is false then return missing value
	return item 1 of pChoice
end choosePlaylistName

on doShuffle()
	-- NOTE: bulk property reads must use the reference form
	-- ("artist of every track of ..."), never a resolved list.
	set srcChoice to choose from list {"Entire Library", "Pick a Playlist"} with prompt "Shuffle songs from:"
	if srcChoice is false then return
	set fromLibrary to ((item 1 of srcChoice) is "Entire Library")
	set limitN to 0
	
	if fromLibrary then
		set sizeChoice to choose from list {"All songs", "Random 100", "Random 250", "Random 500", "Random 1000"} with prompt "How many songs should the SeTeR Shuffle playlist hold?" default items {"All songs"}
		if sizeChoice is false then return
		set sizeText to item 1 of sizeChoice
		if sizeText is not "All songs" then set limitN to (text 8 thru -1 of sizeText) as integer
		tell application "Music"
			set songTracks to every track of library playlist 1 whose media kind is song
			set songArtists to artist of every track of library playlist 1 whose media kind is song
		end tell
	else
		set pName to my choosePlaylistName("Pick a playlist to shuffle:")
		if pName is missing value then return
		tell application "Music"
			set songTracks to every track of playlist pName whose media kind is song
			set songArtists to artist of every track of playlist pName whose media kind is song
		end tell
	end if
	
	set n to count of songTracks
	if n is 0 then
		display dialog "No songs found in that source." buttons {"OK"} default button "OK"
		return
	end if
	
	-- Optional random subset (library mode)
	if limitN > 0 and limitN < n then
		set idxs to my randomIndexes(n, limitN)
		set subTracks to {}
		set subArtists to {}
		repeat with i from 1 to limitN
			set k to item i of idxs
			set end of subTracks to item k of songTracks
			set end of subArtists to item k of songArtists
		end repeat
		set songTracks to subTracks
		set songArtists to subArtists
		set n to limitN
	end if
	
	-- No-repeat-artist option
	set avoidSameArtist to false
	set artistQ to display dialog "Avoid the same artist twice in a row?" buttons {"No", "Yes"} default button "Yes" with title "SeTeR Shuffle"
	if button returned of artistQ is "Yes" then set avoidSameArtist to true
	
	display notification "Shuffling " & n & " songs…" with title "SeTeR Shuffle"
	set finalTracks to my shuffleTrackRefs(songTracks, songArtists, avoidSameArtist)
	
	display notification "Building playlist — " & n & " songs, this takes a bit…" with title "SeTeR Shuffle"
	if fromLibrary then
		set destName to "SeTeR Shuffle"
		tell application "Music"
			-- Reuse the playlist in place so its artwork/description survive.
			if exists playlist destName then
				set destPl to playlist destName
			else
				set destPl to make new user playlist with properties {name:destName}
			end if
		end tell
		my assertUserPlaylist(destPl)
		-- Tracks come from the library, so no staging is needed.
		my buildPlaylist(destPl, finalTracks, false)
	else
		set destName to pName
		tell application "Music" to set destPl to playlist pName
		my assertUserPlaylist(destPl)
		-- SAFETY: snapshot, build, verify, restore on failure.
		set snapshot to my snapshotPlaylist(destPl, destName)
		set snapCount to item 1 of snapshot
		set snapIDs to item 2 of snapshot
		if not (my rewritePlaylistSafely(destPl, destName, finalTracks, snapCount, snapIDs, snapIDs)) then
			display dialog "Shuffle failed — your playlist was restored from backup (details in ~/Library/Logs/seter-shuffle.log)." buttons {"OK"} default button "OK" with icon caution with title "SeTeR Shuffle"
			return
		end if
	end if
	my stampDescription(destPl, "Last reshuffled: ")
	display notification destName & " shuffled — " & n & " songs." with title "SeTeR Shuffle"
end doShuffle

-- Removes repeated songs (same library track listed twice) from a playlist,
-- keeping the original order.
on doRemoveDuplicates()
	set pName to my choosePlaylistName("Remove duplicate songs from:")
	if pName is missing value then return
	tell application "Music"
		set destPl to playlist pName
		set plTracks to every track of destPl whose media kind is song
		set plArtists to artist of every track of destPl whose media kind is song
	end tell
	my assertUserPlaylist(destPl)
	set dedupeResult to my dedupeTrackRefs(destPl, plTracks, plArtists)
	set uniqTracks to item 1 of dedupeResult
	set dupeCount to item 3 of dedupeResult
	set uniqIDs to item 4 of dedupeResult
	if dupeCount is 0 then
		display dialog "No duplicates found in \"" & pName & "\"." buttons {"OK"} default button "OK" with title "SeTeR Shuffle"
		return
	end if
	set q to display dialog "Found " & dupeCount & " repeated song(s) in \"" & pName & "\"." & return & return & "Remove them? (Only the extra copies in this playlist go. Your library isn't touched, and the order is kept.)" buttons {"Cancel", "Remove"} default button "Cancel" with title "SeTeR Shuffle"
	if button returned of q is not "Remove" then return
	set snapshot to my snapshotPlaylist(destPl, pName)
	set snapIDs to item 2 of snapshot
	if not (my rewritePlaylistSafely(destPl, pName, uniqTracks, count of uniqTracks, uniqIDs, snapIDs)) then
		display dialog "Cleanup failed — your playlist was restored from backup (details in ~/Library/Logs/seter-shuffle.log)." buttons {"OK"} default button "OK" with icon caution with title "SeTeR Shuffle"
		return
	end if
	my logLine("removed " & dupeCount & " duplicate(s) from \"" & pName & "\"")
	display notification "Removed " & dupeCount & " duplicate(s) from " & pName & "." with title "SeTeR Shuffle"
end doRemoveDuplicates

-- Puts a playlist back the way it was before the last in-place shuffle/cleanup,
-- using ~/Library/Logs/seter-shuffle-backup.txt.
on doUndo()
	set backupPath to (POSIX path of (path to home folder)) & "Library/Logs/seter-shuffle-backup.txt"
	set rawText to ""
	try
		set rawText to do shell script "cat " & quoted form of backupPath
	end try
	if rawText is "" then
		display dialog "There's no backup to restore yet. One is saved every time SeTeR changes a playlist in place." buttons {"OK"} default button "OK" with title "SeTeR Shuffle"
		return
	end if
	set plName to ""
	set bkDate to "an earlier run"
	set idList to {}
	repeat with ln in paragraphs of rawText
		set lnText to ln as text
		if lnText starts with "# Playlist: " then
			try
				set plName to text 13 thru -1 of lnText
			end try
		else if lnText starts with "# Date: " then
			try
				set bkDate to text 9 thru -1 of lnText
			end try
		else if lnText is not "" and lnText does not start with "#" then
			set end of idList to lnText
		end if
	end repeat
	if plName is "" or (count of idList) is 0 then
		display dialog "The backup file is empty or unreadable, so nothing was changed." buttons {"OK"} default button "OK" with icon caution with title "SeTeR Shuffle"
		return
	end if
	set q to display dialog "Restore \"" & plName & "\" to the " & (count of idList) & " songs it had on " & bkDate & "?" & return & return & "This replaces the playlist's current songs with the backed-up list, in its original order. (Undo can't be undone, since the backup is replaced by later runs.)" buttons {"Cancel", "Restore"} default button "Cancel" with icon caution with title "SeTeR Shuffle"
	if button returned of q is not "Restore" then return
	tell application "Music"
		if exists playlist plName then
			set destPl to playlist plName
		else
			set destPl to make new user playlist with properties {name:plName}
		end if
	end tell
	my assertUserPlaylist(destPl)
	set restored to my restorePlaylistFromBackup(destPl, plName, idList)
	display dialog "Restored " & restored & " of " & (count of idList) & " songs to \"" & plName & "\"." buttons {"OK"} default button "OK" with title "SeTeR Shuffle"
end doUndo

-- ---------------------------------------------------------------------------
-- DAILY MODE
-- ---------------------------------------------------------------------------

on doDailyShuffle(targetName)
	tell application "Music"
		if not (exists playlist targetName) then
			error "Playlist \"" & targetName & "\" not found."
		end if
		set destPl to playlist targetName
		set songTracks to every track of destPl whose media kind is song
		set songArtists to artist of every track of destPl whose media kind is song
	end tell
	my assertUserPlaylist(destPl)
	-- Dedupe by persistent ID (safe: exact track identity, never metadata).
	set dedupeResult to my dedupeTrackRefs(destPl, songTracks, songArtists)
	set songTracks to item 1 of dedupeResult
	set songArtists to item 2 of dedupeResult
	set dupesRemoved to item 3 of dedupeResult
	set uniqueIDs to item 4 of dedupeResult
	set n to count of songTracks
	if n is 0 then error "No songs in \"" & targetName & "\"."
	-- SAFETY: back up the playlist exactly as it is now (duplicates included) so a
	-- restore puts everything back. Verification, however, expects the deduped set.
	set snapshot to my snapshotPlaylist(destPl, targetName)
	set snapCount to item 1 of snapshot
	set snapIDs to item 2 of snapshot
	my logLine("snapshot \"" & targetName & "\" (" & snapCount & " songs backed up)")
	set finalTracks to my shuffleTrackRefs(songTracks, songArtists, true)
	if not (my rewritePlaylistSafely(destPl, targetName, finalTracks, n, uniqueIDs, snapIDs)) then
		error "Shuffle failed for \"" & targetName & "\", playlist restored from backup. Aborting."
	end if
	my stampDescription(destPl, "Last reshuffled: ")
	set logMsg to "shuffled \"" & targetName & "\" (" & n & " songs)"
	if dupesRemoved > 0 then set logMsg to logMsg & " [removed " & dupesRemoved & " duplicate(s)]"
	my logLine(logMsg)
	display notification targetName & " shuffled — " & n & " songs." with title "SeTeR Shuffle"
end doDailyShuffle

-- ---------------------------------------------------------------------------
-- SHUFFLE / BUILD / DEDUPE
-- ---------------------------------------------------------------------------

-- howMany distinct random numbers from 1..c (partial Fisher-Yates).
on randomIndexes(c, howMany)
	if c is 0 or howMany ≤ 0 then return {}
	if howMany > c then set howMany to c
	set idxList to {}
	repeat with i from 1 to c
		set end of idxList to i
	end repeat
	repeat with i from 1 to howMany
		set j to random number from i to c
		set tmp to item i of idxList
		set item i of idxList to item j of idxList
		set item j of idxList to tmp
	end repeat
	set resultList to {}
	repeat with i from 1 to howMany
		set end of resultList to item i of idxList
	end repeat
	return resultList
end randomIndexes

-- Fisher-Yates shuffle. Returns the track refs in the new random order.
-- With avoidSameArtist, a track that repeats the previous artist is swapped with
-- the nearest later track by a different artist (so the order stays close to a
-- true shuffle). Tracks with no artist never count as a repeat. If only
-- same-artist tracks remain at the very end, they stay together; nothing else to do.
on shuffleTrackRefs(songTracks, songArtists, avoidSameArtist)
	set n to count of songTracks
	set order to {}
	repeat with i from 1 to n
		set end of order to i
	end repeat
	repeat with i from n to 2 by -1
		set j to random number from 1 to i
		set tmp to item i of order
		set item i of order to item j of order
		set item j of order to tmp
	end repeat
	if avoidSameArtist and n > 2 then
		repeat with i from 2 to n
			set prevA to item (item (i - 1) of order) of songArtists
			set curA to item (item i of order) of songArtists
			if curA is not "" and curA is prevA then
				repeat with j from (i + 1) to n
					set candA to item (item j of order) of songArtists
					if candA is not prevA then
						set tmp to item i of order
						set item i of order to item j of order
						set item j of order to tmp
						exit repeat
					end if
				end repeat
			end if
		end repeat
	end if
	set finalTracks to {}
	repeat with i from 1 to n
		set end of finalTracks to item (item i of order) of songTracks
	end repeat
	return finalTracks
end shuffleTrackRefs

-- Write trackRefs into destPl in order, replacing its current songs.
-- stageFirst = true  -> trackRefs live INSIDE destPl, so they would go stale when
--   its songs are deleted. They are staged in a temp playlist first, then moved in.
-- stageFirst = false -> trackRefs come from the library (e.g. library shuffle,
--   Rediscover); deleting from destPl doesn't affect them, so no staging needed.
-- Non-song tracks in destPl are preserved; name/artwork/description survive.
-- Throws if destPl isn't a regular playlist, if the finished playlist doesn't hold
-- exactly as many songs as requested, or if the LIBRARY got smaller.
on buildPlaylist(destPl, trackRefs, stageFirst)
	my assertUserPlaylist(destPl)
	set wanted to count of trackRefs
	set libBefore to my librarySize()
	tell application "Music"
		if (count of tracks of destPl) is 0 then
			repeat with t in trackRefs
				duplicate (contents of t) to destPl
			end repeat
		else if stageFirst then
			try
				delete (every user playlist whose name is tempPlaylistName)
			end try
			set tempPl to make new user playlist with properties {name:tempPlaylistName}
			repeat with t in trackRefs
				duplicate (contents of t) to tempPl
			end repeat
			if (count of tracks of tempPl) is not wanted then
				error "Staging failed: temp playlist incomplete."
			end if
			delete (every track of destPl whose media kind is song)
			repeat with t in (every track of tempPl)
				duplicate (contents of t) to destPl
			end repeat
			delete tempPl
		else
			delete (every track of destPl whose media kind is song)
			repeat with t in trackRefs
				duplicate (contents of t) to destPl
			end repeat
		end if
		set finalCount to count of (every track of destPl whose media kind is song)
		if finalCount is not wanted then
			error "Build incomplete: playlist holds " & finalCount & " songs, expected " & wanted & "."
		end if
		if not isDaily then reveal destPl
	end tell
	set libAfter to my librarySize()
	if libAfter < libBefore then
		my logLine("LIBRARY SHRANK during rewrite: " & libBefore & " -> " & libAfter & " tracks")
		error "Your library went from " & libBefore & " to " & libAfter & " tracks during this run. Stopped. Check ~/Documents/SeTeRShuffle/backups/ for the library manifest."
	end if
end buildPlaylist

-- Dedupe track refs by persistent ID, keeping the first occurrence.
-- Safe: persistent ID is the track's true identity, so unlike metadata matching
-- it cannot false-positive when iCloud sync leaves metadata unreliable. Tracks
-- whose ID can't be read are always kept, never treated as duplicates.
-- Returns {uniqueTracks, uniqueArtists, dupeCount, uniqueIDs}; uniqueIDs lists
-- the IDs of the kept tracks (for verification).
on dedupeTrackRefs(destPl, trackRefs, artistList)
	-- Bulk PID read: one AppleEvent instead of thousands (fast).
	set allPIDs to missing value
	try
		tell application "Music"
			set allPIDs to persistent ID of every track of destPl whose media kind is song
		end tell
	end try
	if allPIDs is missing value or (count of allPIDs) is not (count of trackRefs) then
		-- Bulk failed; fall back to single reads.
		set allPIDs to {}
		tell application "Music"
			repeat with t in trackRefs
				try
					set end of allPIDs to persistent ID of (contents of t)
				on error
					set end of allPIDs to missing value
				end try
			end repeat
		end tell
	end if
	-- Filter in pure AppleScript (no app events).
	set uniqueTracks to {}
	set uniqueArtists to {}
	set uniqueIDs to {}
	set seenIDs to {}
	set dupeCount to 0
	repeat with i from 1 to count of trackRefs
		set pid to item i of allPIDs
		set tr to contents of (item i of trackRefs)
		if pid is missing value or pid is "" then
			-- Unidentifiable: keep it, never dedupe.
			set end of uniqueTracks to tr
			set end of uniqueArtists to item i of artistList
		else if seenIDs contains pid then
			set dupeCount to dupeCount + 1
		else
			set end of seenIDs to pid
			set end of uniqueIDs to pid
			set end of uniqueTracks to tr
			set end of uniqueArtists to item i of artistList
		end if
	end repeat
	return {uniqueTracks, uniqueArtists, dupeCount, uniqueIDs}
end dedupeTrackRefs

-- ---------------------------------------------------------------------------
-- REDISCOVER
-- ---------------------------------------------------------------------------

-- Rediscover candidates, tiered by signal strength:
--   tier 1: 2+ plays, unplayed for staleDays+ days (forgotten favorites)
--   tier 2: 1 play, unplayed for staleDays+ days (one-time listens gathering dust)
--   tier 3: 0 plays, added staleDays+ days ago (never got around to it)
-- Fills up to rediscoverTarget(library size) picks, best tier first.
-- Returns possibly-empty list.
on findRediscoverPicks()
	tell application "Music"
		set libTracks to every track of library playlist 1 whose media kind is song
		set playCounts to played count of every track of library playlist 1 whose media kind is song
		set playDates to played date of every track of library playlist 1 whose media kind is song
		set addedDates to date added of every track of library playlist 1 whose media kind is song
	end tell
	
	set cutoff to (current date) - staleDays * days
	set tier1 to {}
	set tier2 to {}
	set tier3 to {}
	repeat with i from 1 to count of libTracks
		set pc to item i of playCounts
		set pd to item i of playDates
		set stale to (pd is missing value or pd < cutoff)
		if pc ≥ 2 and stale then
			set end of tier1 to item i of libTracks
		else if pc is 1 and stale then
			set end of tier2 to item i of libTracks
		else if pc is 0 then
			set ad to item i of addedDates
			if ad is missing value or ad < cutoff then
				set end of tier3 to item i of libTracks
			end if
		end if
	end repeat
	
	set targetSize to my rediscoverTarget(count of libTracks)
	set picks to my pickRandom(tier1, targetSize)
	set remaining to targetSize - (count of picks)
	if remaining > 0 then set picks to picks & my pickRandom(tier2, remaining)
	set remaining to targetSize - (count of picks)
	if remaining > 0 then set picks to picks & my pickRandom(tier3, remaining)
	return picks
end findRediscoverPicks

-- How many songs SeTeR Rediscover should hold for a library of libCount songs:
-- rediscoverPercent % of the library, clamped to rediscoverMin..rediscoverMax.
on rediscoverTarget(libCount)
	set sz to round (libCount * rediscoverPercent / 100) rounding to nearest
	if sz < rediscoverMin then set sz to rediscoverMin
	if sz > rediscoverMax then set sz to rediscoverMax
	return sz
end rediscoverTarget

-- Up to howMany random items from someList.
on pickRandom(someList, howMany)
	set idxs to my randomIndexes(count of someList, howMany)
	set resultList to {}
	repeat with i from 1 to count of idxs
		set end of resultList to item (item i of idxs) of someList
	end repeat
	return resultList
end pickRandom

on writeRediscoverPlaylist(picks)
	tell application "Music"
		if exists playlist "SeTeR Rediscover" then
			set newPl to playlist "SeTeR Rediscover"
		else
			set newPl to make new user playlist with properties {name:"SeTeR Rediscover"}
		end if
	end tell
	-- Picks come from the library, so no staging needed.
	my buildPlaylist(newPl, picks, false)
	my stampDescription(newPl, "Last refreshed: ")
end writeRediscoverPlaylist

-- ---------------------------------------------------------------------------
-- DESCRIPTION STAMP / DATES
-- ---------------------------------------------------------------------------

-- Stamp the playlist description with a "Last reshuffled/refreshed: <date>"
-- line, preserving any existing description text. Failure here (e.g. a
-- read-only description) is logged but never fails the shuffle itself.
on stampDescription(destPl, stampLabel)
	try
		tell application "Music"
			set oldDesc to description of destPl
		end tell
		if oldDesc is missing value then set oldDesc to ""
		set keptLines to {}
		repeat with ln in paragraphs of oldDesc
			set lnText to ln as text
			if lnText does not start with "Last reshuffled:" and lnText does not start with "Last refreshed:" then
				set end of keptLines to lnText
			end if
		end repeat
		repeat while (count of keptLines) > 0 and (last item of keptLines) is ""
			if (count of keptLines) is 1 then
				set keptLines to {}
			else
				set keptLines to items 1 thru -2 of keptLines
			end if
		end repeat
		set stampLine to stampLabel & my dateStamp()
		if (count of keptLines) > 0 then
			set end of keptLines to ""
			set end of keptLines to stampLine
		else
			set keptLines to {stampLine}
		end if
		set AppleScript's text item delimiters to return
		set newDesc to keptLines as text
		set AppleScript's text item delimiters to ""
		tell application "Music"
			set description of destPl to newDesc
		end tell
	on error errMsg
		set AppleScript's text item delimiters to ""
		my logLine("note: couldn't update description (" & errMsg & ")")
	end try
end stampDescription

on dateStamp()
	set d to current date
	return (month of d as text) & " " & (day of d as text) & ", " & (year of d as text) & " at " & my clockText(d)
end dateStamp

on clockText(d)
	set h to hours of d
	set m to minutes of d
	set ampm to "AM"
	if h ≥ 12 then set ampm to "PM"
	if h > 12 then set h to h - 12
	if h is 0 then set h to 12
	set mStr to m as text
	if m < 10 then set mStr to "0" & mStr
	return (h as text) & ":" & mStr & " " & ampm
end clockText

on doRediscover()
	set picks to my findRediscoverPicks()
	if (count of picks) is 0 then
		display dialog "Nothing to rediscover — everything in your library was played or added recently." buttons {"OK"} default button "OK" with title "SeTeR Shuffle"
		return
	end if
	my writeRediscoverPlaylist(picks)
	display notification "SeTeR Rediscover ready — " & (count of picks) & " songs." with title "SeTeR Shuffle"
end doRediscover

on doDailyRediscover()
	set picks to my findRediscoverPicks()
	if (count of picks) is 0 then
		my logLine("rediscover: nothing to rediscover")
		return
	end if
	my writeRediscoverPlaylist(picks)
	my logLine("rediscover: updated (" & (count of picks) & " songs)")
	display notification "SeTeR Rediscover updated — " & (count of picks) & " songs." with title "SeTeR Shuffle"
end doDailyRediscover
