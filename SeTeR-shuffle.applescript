-- SeTeR Shuffle v2.6
-- True-random (Fisher-Yates) shuffle for Apple Music.
--
-- WHAT'S NEW IN v2.6
--     * Smarter Rediscover. Songs are now scored instead of sorted into three
--       fixed tiers: more plays, a favorite or 4-5 star rating, and a longer
--       time forgotten all make a song likelier to come back. Disliked,
--       unchecked and skip-heavy songs are left out. No more than
--       rediscoverMaxPerArtist songs per artist, and songs picked in the last
--       rediscoverCooldownDays days aren't picked again, so the daily refresh
--       stays fresh. The playlist is now shuffled with artists spread out
--       (it used to play best-tier first). A song Music can't add is skipped
--       instead of failing the whole refresh. Full rules: see REDISCOVER below.
--     * Preview: osascript SeTeR-shuffle.applescript rediscover-preview
--       shows what Rediscover would pick without changing anything.
--     * setup.sh installs everything, builds the apps and schedules the daily run.
--
-- EXPERIMENTAL (not a stable version bump; the script still reports v2.6):
--   * Flow mode (2026-10-28, untested on a Mac — see CHANGELOG-EXPERIMENTAL.md).
--     osascript SeTeR-shuffle.applescript flow builds/refreshes a "SeTeR Flow"
--     playlist from the library, ordered so the vibe flows: mid-energy start,
--     a rise to a peak around two-thirds through, then an ease-down ending.
--     Energy comes only from real Music track properties (bpm, genre, year,
--     played count, rating, favorited). flowPreview prints the would-be order
--     without changing anything. Flow writes through the same
--     snapshot/verify/restore path as every other in-place change.
--     DO NOT install this over a stable build until a Mac run proves it.
--
-- WHAT'S NEW IN v2.5
--     * Better "avoid the same artist" logic. The old pass only stopped an artist
--       from playing back-to-back, and fixed clashes by pulling in the next
--       different-artist song, which dragged big artists toward the end of the list.
--       Now clashes are repaired by swapping with a RANDOM song anywhere in the
--       list (only if it strictly improves things), so artists stay spread out
--       evenly. New setting artistSpacing keeps at least that many songs between
--       two songs by the same artist (best effort; 1 = just not back-to-back).
--     * "Artist feat. Someone" now counts as "Artist" (setting
--       featuringIsSameArtist), so a featured track no longer sneaks in next to
--       the main artist's songs.
--
-- WHAT'S NEW IN v2.4
--   * The daily run now lists every duplicate it removes (artist - title) in the log,
--     and its notification says how many were removed, so a drop in song count is
--     never a mystery. New setting dailyRemoveDuplicates (below) turns duplicate
--     removal off entirely if you'd rather keep every entry.
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
--   Rediscover: songs you used to love and forgot (weighted by plays, favorites,
--     ratings and time forgotten; see REDISCOVER below) go into
--     "SeTeR Rediscover", shuffled with artists spread out. It always fills up
--     to its target size (1% of your library, between 30 and 500 songs). Kept in
--     place so its cover artwork survives.
--
-- AUTOMATIC (daily): osascript SeTeR-shuffle.applescript daily "Playlist Name"
--   Backs up a library manifest (once a day), shuffles the named playlist in
--   place (removing duplicates unless dailyRemoveDuplicates is false) AND refreshes "SeTeR Rediscover", no dialogs.
--   Progress and errors go to ~/Library/Logs/seter-shuffle.log. See
--   com.seter.daily.plist for the scheduled job (daily at 8:00 AM).
--
-- INSTALL (easiest): run setup.sh from the repo (bash setup.sh). Or by hand:
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
property rediscoverMaxPerArtist : 3 -- Rediscover holds at most this many songs per artist (0 = no limit)
property rediscoverCooldownDays : 14 -- a song Rediscover picked isn't picked again for this many days (0 = off)
property backupKeepDays : 14 -- how long library manifests are kept
property defaultDailyPlaylist : "my new sandwich recipe"
property dailyRemoveDuplicates : true -- true: the daily run removes repeated songs from the playlist; false: keeps every entry
property artistSpacing : 2 -- "avoid same artist" keeps at least this many songs between an artist's songs (1 = just not back-to-back)
property featuringIsSameArtist : true -- true: "Artist feat. X" counts as "Artist" when spacing artists apart
property flowSize : 50 -- "SeTeR Flow" holds at most this many songs
property flowPoolMax : 400 -- Flow sequences from at most this many eligible library songs (a random pool when the library is bigger), so the greedy ordering stays fast

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
	else if (count of argv) > 0 and (item 1 of argv) is "flow" then
		-- Terminal: builds/refreshes "SeTeR Flow". Dialogs stay off (isDaily
		-- is only a dialog/log switch here); the result text is returned.
		set isDaily to true
		try
			return my doFlow()
		on error errMsg
			my logLine("ERROR (flow): " & errMsg)
			return "Flow failed: " & errMsg
		end try
	else if (count of argv) > 0 and (item 1 of argv) is "flowPreview" then
		-- Read-only dry run: prints the would-be Flow order, changes nothing.
		set isDaily to true
		try
			return my previewFlow()
		on error errMsg
			my logLine("ERROR (flowPreview): " & errMsg)
			return "Flow preview failed: " & errMsg
		end try
	else if (count of argv) > 0 and (item 1 of argv) is "rediscover-preview" then
		-- Read-only dry run for the Terminal: prints what Rediscover would pick.
		set isDaily to true
		return my previewRediscover()
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
	set modeChoice to choose from list {"🔀 Shuffle", "💡 Rediscover", "🌊 Flow", "🧹 Remove duplicates", "↩️ Undo last shuffle"} with prompt "What should SeTeR do?"
	if modeChoice is false then return
	set m to item 1 of modeChoice
	if m is "🔀 Shuffle" then
		my doShuffle()
	else if m is "💡 Rediscover" then
		my doRediscover()
	else if m is "🌊 Flow" then
		my doFlowMenu()
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
	if (count of songTracks) is 0 then error "No songs in \"" & targetName & "\"."
	-- SAFETY: back up the playlist exactly as it is now (duplicates included) so a
	-- restore puts everything back.
	set snapshot to my snapshotPlaylist(destPl, targetName)
	set snapCount to item 1 of snapshot
	set snapIDs to item 2 of snapshot
	my logLine("snapshot \"" & targetName & "\" (" & snapCount & " songs backed up)")
	set dupesRemoved to 0
	set expectedIDs to snapIDs
	if dailyRemoveDuplicates then
		-- Dedupe by persistent ID (exact track identity, never metadata).
		set dedupeResult to my dedupeTrackRefs(destPl, songTracks, songArtists)
		set songTracks to item 1 of dedupeResult
		set songArtists to item 2 of dedupeResult
		set dupesRemoved to item 3 of dedupeResult
		set expectedIDs to item 4 of dedupeResult
		set removedLabels to item 5 of dedupeResult
		repeat with i from 1 to count of removedLabels
			if i > 50 then
				my logLine("... and " & ((count of removedLabels) - 50) & " more duplicate(s)")
				exit repeat
			end if
			my logLine("removing duplicate: " & (item i of removedLabels))
		end repeat
	end if
	set n to count of songTracks
	set finalTracks to my shuffleTrackRefs(songTracks, songArtists, true)
	if not (my rewritePlaylistSafely(destPl, targetName, finalTracks, n, expectedIDs, snapIDs)) then
		error "Shuffle failed for \"" & targetName & "\", playlist restored from backup. Aborting."
	end if
	my stampDescription(destPl, "Last reshuffled: ")
	set logMsg to "shuffled \"" & targetName & "\" (" & n & " songs)"
	if dupesRemoved > 0 then set logMsg to logMsg & " [removed " & dupesRemoved & " duplicate(s)]"
	my logLine(logMsg)
	set noteText to targetName & " shuffled — " & n & " songs."
	if dupesRemoved > 0 then set noteText to targetName & " shuffled — " & n & " songs (" & dupesRemoved & " duplicate(s) removed)."
	display notification noteText with title "SeTeR Shuffle"
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
-- With avoidSameArtist, the shuffled order is then repaired by spreadArtists()
-- so songs by the same artist are kept apart (see below). Tracks with no artist
-- never count as a clash.
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
		set order to my spreadArtists(order, my artistKeyList(songArtists), artistSpacing)
	end if
	set finalTracks to {}
	repeat with i from 1 to n
		set end of finalTracks to item (item i of order) of songTracks
	end repeat
	return finalTracks
end shuffleTrackRefs

-- Artist names to compare when spacing artists apart. With featuringIsSameArtist,
-- "Artist feat. X" / "Artist (ft. X)" are cut down to "Artist".
on artistKeyList(songArtists)
	set outList to {}
	repeat with a in songArtists
		set end of outList to my artistKey(contents of a)
	end repeat
	return outList
end artistKeyList

on artistKey(a)
	if a is missing value then return ""
	set s to a as text
	if not featuringIsSameArtist then return s
	-- Quick exit for the (vast majority of) names with no "feat"/"ft" in them.
	if (offset of " f" in s) is 0 and (offset of " (f" in s) is 0 then return s
	repeat with m in {" feat.", " feat ", " ft.", " ft ", " featuring", " (feat", " (ft"}
		set p to offset of (contents of m) in s
		if p > 1 then set s to text 1 thru (p - 1) of s
	end repeat
	return s
end artistKey

-- Does the song at position p share an artist with any of the next "spacing" songs?
on clashesAt(order, keyList, p, n, spacing)
	if p < 1 or p > (n - 1) then return false
	set a to item (item p of order) of keyList
	if a is "" then return false
	set lastQ to p + spacing
	if lastQ > n then set lastQ to n
	repeat with q from (p + 1) to lastQ
		if (item (item q of order) of keyList) is a then return true
	end repeat
	return false
end clashesAt

-- Clash count over every position whose answer can change when positions i and j
-- are swapped (the "spacing" positions before each, plus each itself).
on localClashes(order, keyList, n, spacing, i, j)
	set c to 0
	set loI to i - spacing
	repeat with p from loI to i
		if my clashesAt(order, keyList, p, n, spacing) then set c to c + 1
	end repeat
	repeat with p from (j - spacing) to j
		if p < loI or p > i then
			if my clashesAt(order, keyList, p, n, spacing) then set c to c + 1
		end if
	end repeat
	return c
end localClashes

-- Spread same-artist songs apart WITHOUT disturbing the randomness of the shuffle.
-- For each song that clashes with a nearby song by the same artist, try swapping
-- it with a random song from ANYWHERE in the list and keep the swap only if the
-- number of clashes goes down. Repeats for a few passes. Because partners are
-- picked uniformly, artists end up evenly spread (no pile-up at the end) and it
-- works even for the last songs in the list. It's best effort: an artist who
-- makes up most of the playlist can't be fully separated, and the work is capped
-- so that case can't make a run drag on.
on spreadArtists(order, keyList, spacing)
	set n to count of order
	if spacing > (n - 1) then set spacing to n - 1
	if spacing < 1 then return order
	set attemptsLeft to 20000
	set lastBad to -1
	repeat with passNo from 1 to 6
		set bad to 0
		repeat with p from 1 to (n - 1)
			if my clashesAt(order, keyList, p, n, spacing) then
				set fixedIt to false
				repeat 30 times
					if attemptsLeft < 1 then exit repeat
					set attemptsLeft to attemptsLeft - 1
					set j to random number from 1 to n
					if j is not p then
						set clashesBefore to my localClashes(order, keyList, n, spacing, p, j)
						set tmp to item p of order
						set item p of order to item j of order
						set item j of order to tmp
						set clashesAfter to my localClashes(order, keyList, n, spacing, p, j)
						if clashesAfter < clashesBefore then
							set fixedIt to true
							exit repeat
						end if
						-- no improvement: undo the swap
						set tmp to item p of order
						set item p of order to item j of order
						set item j of order to tmp
					end if
				end repeat
				if not fixedIt then set bad to bad + 1
			end if
		end repeat
		if bad is 0 then exit repeat
		if lastBad ≥ 0 and bad ≥ lastBad then exit repeat
		if attemptsLeft < 1 then exit repeat
		set lastBad to bad
	end repeat
	return order
end spreadArtists

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
-- Returns {uniqueTracks, uniqueArtists, dupeCount, uniqueIDs, removedLabels};
-- uniqueIDs lists the IDs of the kept tracks (for verification) and removedLabels
-- has an "Artist - Title" entry for each removed duplicate (for the log).
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
	set removedLabels to {}
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
			set dupTitle to "(unknown title)"
			try
				tell application "Music" to set dupTitle to name of tr
			end try
			set end of removedLabels to (my safeText(item i of artistList)) & " - " & dupTitle
		else
			set end of seenIDs to pid
			set end of uniqueIDs to pid
			set end of uniqueTracks to tr
			set end of uniqueArtists to item i of artistList
		end if
	end repeat
	return {uniqueTracks, uniqueArtists, dupeCount, uniqueIDs, removedLabels}
end dedupeTrackRefs


-- ---------------------------------------------------------------------------
-- FLOW (EXPERIMENTAL, 2026-10-28 — untested on a Mac)
-- ---------------------------------------------------------------------------
--
-- "SeTeR Flow" is a curated playlist whose order flows with the vibe of the
-- songs instead of being shuffled. Source: the whole library (not the daily
-- playlist), so there is enough variety to shape an arc. Every song gets an
-- energy score from real Music properties only, then a greedy pass walks a
-- wave arc: mid-energy start, rising to a peak around two-thirds through,
-- easing down at the end. Each step prefers a small energy change, the same
-- or a related genre, and a nearby year, and it never puts the same artist
-- within artistSpacing songs of their last song (best effort, like the
-- shuffle's spacing rule).
--
-- Energy model (plain words; see CHANGELOG-EXPERIMENTAL.md for the table):
--   * BPM bands set the base (slow = calm, fast = high energy); missing BPM
--     defaults to mid-energy (50), never to 0.
--   * Genre nudges the base up for rock / hip-hop / dance / electronic and
--     down for classical / ambient; everything else stays near its BPM base.
--   * Familiarity nudges it a little: lots of plays, a 4-5 star rating, or a
--     favorite push it up; a 1-2 star rating pulls it down.
--   * The result is clamped to 5..100, so no song is ever silent or maxed out
--     by a single missing field.
-- Safety: Flow writes ONLY through rewritePlaylistSafely (snapshot before,
-- verify after, restore from the snapshot on any failure), the same path the
-- daily shuffle and dedupe use. There is no second safety path. The library
-- size check inside buildPlaylist also runs. flowPreview changes nothing.

-- Genre groups used for the "same or related genre" preference.
-- 1 rock/metal/punk/alternative, 2 hip-hop/rap/R&B, 3 pop/dance/electronic,
-- 4 jazz/soul/funk/blues, 5 country/folk/americana, 6 classical/ambient/
-- instrumental/lo-fi, 7 anything else / unknown.
on flowGenreGroup(genreText)
	if genreText is missing value then return 7
	set s to genreText as text
	if s is "" then return 7
	if (offset of "metal" in s) > 0 or (offset of "punk" in s) > 0 or (offset of "rock" in s) > 0 or (offset of "alternative" in s) > 0 then return 1
	if (offset of "hip-hop" in s) > 0 or (offset of "hip hop" in s) > 0 or (offset of "rap" in s) > 0 or (offset of "r&b" in s) > 0 or (offset of "rhythm" in s) > 0 then return 2
	if (offset of "dance" in s) > 0 or (offset of "electronic" in s) > 0 or (offset of "edm" in s) > 0 or (offset of "pop" in s) > 0 then return 3
	if (offset of "jazz" in s) > 0 or (offset of "soul" in s) > 0 or (offset of "funk" in s) > 0 or (offset of "blues" in s) > 0 then return 4
	if (offset of "country" in s) > 0 or (offset of "folk" in s) > 0 or (offset of "americana" in s) > 0 then return 5
	if (offset of "classical" in s) > 0 or (offset of "ambient" in s) > 0 or (offset of "instrumental" in s) > 0 or (offset of "lo-fi" in s) > 0 or (offset of "lofi" in s) > 0 or (offset of "chill" in s) > 0 then return 6
	return 7
end flowGenreGroup

on flowGenresRelated(g1, g2)
	if g1 is g2 then return true
	if (g1 is 1 and g2 is 3) or (g1 is 3 and g2 is 1) then return true
	if (g1 is 2 and g2 is 3) or (g1 is 3 and g2 is 2) then return true
	if (g1 is 4 and g2 is 6) or (g1 is 6 and g2 is 4) then return true
	if (g1 is 5 and g2 is 6) or (g1 is 6 and g2 is 5) then return true
	return false
end flowGenresRelated

-- Energy score, 5..100, from bpm / genre / plays / rating / favorite only.
on flowEnergy(bpmVal, genreText, playCount, ratingVal, favFlag)
	set energy to 50
	if bpmVal is not missing value and bpmVal > 0 then
		if bpmVal < 80 then
			set energy to 25
		else if bpmVal < 100 then
			set energy to 40
		else if bpmVal < 120 then
			set energy to 55
		else if bpmVal < 140 then
			set energy to 75
		else if bpmVal < 160 then
			set energy to 85
		else
			set energy to 95
		end if
	end if
	set g to my flowGenreGroup(genreText)
	if g is 1 or g is 3 then
		set energy to energy + 8
	else if g is 2 then
		set energy to energy + 5
	else if g is 4 then
		set energy to energy - 5
	else if g is 5 then
		set energy to energy - 3
	else if g is 6 then
		set energy to energy - 12
	end if
	if playCount is not missing value and playCount ≥ 20 then set energy to energy + 5
	if ratingVal is not missing value then
		if ratingVal ≥ 80 then
			set energy to energy + 5
		else if ratingVal ≥ 1 and ratingVal ≤ 40 then
			set energy to energy - 10
		end if
	end if
	if favFlag is true then set energy to energy + 5
	if energy < 5 then set energy to 5
	if energy > 100 then set energy to 100
	return energy
end flowEnergy

-- Wave-arc target energy at position pos of total: 45 at the start, rising to
-- 90 at the two-thirds peak, easing down to 40 at the end.
on flowTargetEnergy(pos, total)
	if total ≤ 1 then return 50
	set riseEnd to (total * 2) div 3
	if riseEnd < 2 then set riseEnd to 2
	if riseEnd > total then set riseEnd to total
	if pos ≤ riseEnd then
		if riseEnd is 1 then return 90
		return 45 + 45 * (pos - 1) / (riseEnd - 1)
	else
		if total is riseEnd then return 90
		return 90 - 50 * (pos - riseEnd) / (total - riseEnd)
	end if
end flowTargetEnergy

-- Greedy nearest-neighbor ordering over the pool lists (all parallel lists of
-- the same length). Returns the pool positions in Flow order. Cost per step:
-- |energy - arc target| + genre cost (0 same, 8 related, 20 otherwise) +
-- year cost (0 same decade, 5 adjacent decade, 10 otherwise) + 1000 if the
-- artist appeared within the last artistSpacing picks (so spacing wins over
-- vibe, best effort). Ties keep the earliest pool position.
on flowOrder(poolEnergies, poolGroups, poolYears, poolArtistKeys, total)
	set n to count of poolEnergies
	if total > n then set total to n
	if total ≤ 0 then return {}
	set usedFlags to my filledList(n, false)
	set orderList to {}
	set recentArtists to {}
	set prevGroup to missing value
	set prevYear to missing value
	repeat with pos from 1 to total
		set target to my flowTargetEnergy(pos, total)
		set bestIdx to 0
		set bestCost to 1000000
		repeat with i from 1 to n
			if (item i of usedFlags) is false then
				set cost to 0
				set eDiff to (item i of poolEnergies) - target
				if eDiff < 0 then set eDiff to -eDiff
				set cost to cost + eDiff
				if prevGroup is not missing value then
					set gi to item i of poolGroups
					if gi is prevGroup then
						set cost to cost + 0
					else if my flowGenresRelated(gi, prevGroup) then
						set cost to cost + 8
					else
						set cost to cost + 20
					end if
				end if
				if prevYear is not missing value then
					set yi to item i of poolYears
					if yi is not missing value then
						set d1 to (prevYear div 10) * 10
						set d2 to (yi div 10) * 10
						set decadeDiff to d1 - d2
						if decadeDiff < 0 then set decadeDiff to -decadeDiff
						if decadeDiff is 0 then
							set cost to cost + 0
						else if decadeDiff is 10 then
							set cost to cost + 5
						else
							set cost to cost + 10
						end if
					end if
				end if
				set aKey to item i of poolArtistKeys
				if aKey is not "" and (recentArtists contains aKey) then set cost to cost + 1000
				if cost < bestCost then
					set bestCost to cost
					set bestIdx to i
				end if
			end if
		end repeat
		if bestIdx is 0 then exit repeat
		set item bestIdx of usedFlags to true
		set end of orderList to bestIdx
		set prevGroup to item bestIdx of poolGroups
		set prevYear to item bestIdx of poolYears
		set aKey to item bestIdx of poolArtistKeys
		if aKey is not "" then
			set end of recentArtists to aKey
			repeat while (count of recentArtists) > artistSpacing
				if (count of recentArtists) is 1 then
					set recentArtists to {}
				else
					set recentArtists to items 2 thru -1 of recentArtists
				end if
			end repeat
		end if
	end repeat
	return orderList
end flowOrder

-- Scores the library and returns {finalTracks, finalArtists, finalIDs,
-- finalEnergies, candidateCount, flowCount}, or missing value when nothing
-- is eligible. Changes nothing in Music.
on prepareFlow()
	-- NOTE: bulk property reads must use the reference form, as elsewhere.
	tell application "Music"
		set libTracks to every track of library playlist 1 whose media kind is song
		set libPIDs to persistent ID of every track of library playlist 1 whose media kind is song
		set libArtists to artist of every track of library playlist 1 whose media kind is song
		set libGenres to genre of every track of library playlist 1 whose media kind is song
		set libBPMs to bpm of every track of library playlist 1 whose media kind is song
		set libYears to year of every track of library playlist 1 whose media kind is song
		set libPlayCounts to played count of every track of library playlist 1 whose media kind is song
		set libRatings to rating of every track of library playlist 1 whose media kind is song
	end tell
	set n to count of libTracks
	if n is 0 then return missing value
	-- Optional signals, same pattern as Rediscover: missing = neutral default.
	set libFavFlags to {}
	set libDislikeFlags to {}
	set libEnabledFlags to {}
	try
		tell application "Music" to set libFavFlags to favorited of every track of library playlist 1 whose media kind is song
	on error
		try
			tell application "Music" to set libFavFlags to loved of every track of library playlist 1 whose media kind is song
		end try
	end try
	try
		tell application "Music" to set libDislikeFlags to disliked of every track of library playlist 1 whose media kind is song
	end try
	try
		tell application "Music" to set libEnabledFlags to enabled of every track of library playlist 1 whose media kind is song
	end try
	if (count of libFavFlags) is not n then set libFavFlags to my filledList(n, false)
	if (count of libDislikeFlags) is not n then set libDislikeFlags to my filledList(n, false)
	if (count of libEnabledFlags) is not n then set libEnabledFlags to my filledList(n, true)
	-- Eligible: checked and not disliked. (Skip-heavy songs are NOT excluded
	-- here, unlike Rediscover: a Flow set is about vibe, and a skipped song
	-- can still fit the arc. This is a deliberate, documented difference.)
	set eligIdx to {}
	set eligEnergies to {}
	set eligGroups to {}
	set eligYears to {}
	set eligArtistKeys to {}
	repeat with i from 1 to n
		if (item i of libEnabledFlags) is not false and (item i of libDislikeFlags) is not true then
			set pc to item i of libPlayCounts
			if pc is missing value then set pc to 0
			set rt to item i of libRatings
			if rt is missing value then set rt to 0
			set end of eligIdx to i
			set end of eligEnergies to my flowEnergy(item i of libBPMs, item i of libGenres, pc, rt, item i of libFavFlags)
			set end of eligGroups to my flowGenreGroup(item i of libGenres)
			set end of eligYears to item i of libYears
			set end of eligArtistKeys to my artistKey(item i of libArtists)
		end if
	end repeat
	set m to count of eligIdx
	if m is 0 then return missing value
	-- Bound the greedy pass: a random pool when the library is big.
	set poolPos to {}
	if m > flowPoolMax and flowPoolMax > 0 then
		set poolPos to my randomIndexes(m, flowPoolMax)
	else
		repeat with i from 1 to m
			set end of poolPos to i
		end repeat
	end if
	set poolEnergies to {}
	set poolGroups to {}
	set poolYears to {}
	set poolArtistKeys to {}
	repeat with pp in poolPos
		set k to contents of pp
		set end of poolEnergies to item k of eligEnergies
		set end of poolGroups to item k of eligGroups
		set end of poolYears to item k of eligYears
		set end of poolArtistKeys to item k of eligArtistKeys
	end repeat
	set want to flowSize
	if want < 1 then set want to 1
	set orderList to my flowOrder(poolEnergies, poolGroups, poolYears, poolArtistKeys, want)
	set finalTracks to {}
	set finalArtists to {}
	set finalIDs to {}
	set finalEnergies to {}
	repeat with pp in orderList
		set poolI to contents of pp
		set eligI to item poolI of poolPos
		set libI to item eligI of eligIdx
		set end of finalTracks to item libI of libTracks
		set end of finalArtists to item libI of libArtists
		set end of finalIDs to item libI of libPIDs
		set end of finalEnergies to item poolI of poolEnergies
	end repeat
	return {finalTracks, finalArtists, finalIDs, finalEnergies, m, count of finalTracks}
end prepareFlow

-- Terminal / menu write path: builds or refreshes "SeTeR Flow" through the
-- shared snapshot/verify/restore path. Returns a one-line summary.
on doFlow()
	set prepared to my prepareFlow()
	if prepared is missing value then return "Flow: nothing eligible in the library (no checked, non-disliked songs found)."
	set finalTracks to item 1 of prepared
	set finalIDs to item 3 of prepared
	set flowCount to item 6 of prepared
	tell application "Music"
		if exists playlist "SeTeR Flow" then
			set destPl to playlist "SeTeR Flow"
		else
			set destPl to make new user playlist with properties {name:"SeTeR Flow"}
		end if
	end tell
	my assertUserPlaylist(destPl)
	set snapshot to my snapshotPlaylist(destPl, "SeTeR Flow")
	set snapIDs to item 2 of snapshot
	if not (my rewritePlaylistSafely(destPl, "SeTeR Flow", finalTracks, flowCount, finalIDs, snapIDs)) then
		error "Flow build failed, playlist restored from backup. See ~/Library/Logs/seter-shuffle.log"
	end if
	my stampDescription(destPl, "Last refreshed: ")
	my logLine("flow: updated \"SeTeR Flow\" (" & flowCount & " songs from " & (item 5 of prepared) & " eligible)")
	return "SeTeR Flow ready: " & flowCount & " songs from " & (item 5 of prepared) & " eligible library songs."
end doFlow

-- Menu wrapper for doFlow (dialogs allowed here, unlike the terminal path).
on doFlowMenu()
	try
		set msg to my doFlow()
		display notification msg with title "SeTeR Shuffle"
	on error errMsg number errNum
		my reportError(errMsg, errNum)
	end try
end doFlowMenu

-- Terminal-only dry run: prints the would-be Flow order (first 25, with
-- energy scores) without changing anything in Music.
on previewFlow()
	set prepared to my prepareFlow()
	if prepared is missing value then return "Flow preview: nothing eligible in the library."
	set finalTracks to item 1 of prepared
	set finalArtists to item 2 of prepared
	set finalEnergies to item 4 of prepared
	set total to count of finalTracks
	set outLines to {"Flow preview: " & total & " songs from " & (item 5 of prepared) & " eligible library songs. Nothing was changed.", ""}
	set shown to total
	if shown > 25 then set shown to 25
	repeat with i from 1 to shown
		set t to item i of finalTracks
		tell application "Music"
			set trackName to name of t
		end tell
		set end of outLines to (i as text) & ". " & my safeText(item i of finalArtists) & " - " & my safeText(trackName) & " (energy " & (item i of finalEnergies) & ")"
	end repeat
	if total > shown then set end of outLines to "... and " & (total - shown) & " more"
	set AppleScript's text item delimiters to linefeed
	set outText to outLines as text
	set AppleScript's text item delimiters to ""
	return outText
end previewFlow

-- ---------------------------------------------------------------------------
-- REDISCOVER
-- ---------------------------------------------------------------------------

-- How Rediscover chooses songs (v2.6)
--
-- Every song gets a weight, then the playlist is drawn by weighted random
-- sampling, so likelier songs come up more often but nothing is guaranteed:
--
--   ELIGIBLE: not disliked, not unchecked, not skip-heavy (3+ skips AND more
--     skips than plays), and forgotten: last played staleDays+ days ago (or, for
--     never-played songs, added staleDays+ days ago).
--   WEIGHT = how much you liked it x how long it has been forgotten
--     liked:     never played 0.4; played once 1.5; each extra play +0.5 up to 10
--     boosts:    favorited x3, 4-5 stars x2, 1-2 stars x0.25, each skip divides
--     forgotten: days since last played (or added) / staleDays, capped at 5x
--   VARIETY: at most rediscoverMaxPerArtist songs per artist, and nothing that
--     Rediscover already picked in the last rediscoverCooldownDays days (the
--     picks are remembered in ~/Documents/SeTeRShuffle/rediscover-history.tsv).
--     If the pool is too small to fill the playlist, these two rules are relaxed
--     rather than leaving it short.
--   ORDER: the picks are shuffled (Fisher-Yates) and spread out by artist, so
--     the playlist doesn't play best-songs-first.
--
-- Rating, favorite, dislike, skip and checked-state signals are optional: if
-- the Music app doesn't offer one, it is ignored.

-- Scores the library and picks this run's Rediscover songs.
-- Returns {pickTracks, pickArtists, pickIDs, candidateCount, targetSize};
-- pickTracks is empty when nothing is eligible.
on findRediscoverPicks()
	-- NOTE: bulk property reads must use the reference form
	-- ("played count of every track of ..."), never a resolved list.
	tell application "Music"
		set libTracks to every track of library playlist 1 whose media kind is song
		set libPIDs to persistent ID of every track of library playlist 1 whose media kind is song
		set libArtists to artist of every track of library playlist 1 whose media kind is song
		set playCounts to played count of every track of library playlist 1 whose media kind is song
		set playDates to played date of every track of library playlist 1 whose media kind is song
		set addedDates to date added of every track of library playlist 1 whose media kind is song
	end tell
	set n to count of libTracks
	if n is 0 then return {{}, {}, {}, 0, 0}
	
	-- Optional signals; any the Music app can't provide is replaced by a neutral default.
	set skipCounts to {}
	set ratingList to {}
	set favFlags to {}
	set dislikeFlags to {}
	set enabledFlags to {}
	try
		tell application "Music" to set skipCounts to skipped count of every track of library playlist 1 whose media kind is song
	end try
	try
		tell application "Music" to set ratingList to rating of every track of library playlist 1 whose media kind is song
	end try
	try
		tell application "Music" to set favFlags to favorited of every track of library playlist 1 whose media kind is song
	on error
		try
			tell application "Music" to set favFlags to loved of every track of library playlist 1 whose media kind is song
		end try
	end try
	try
		tell application "Music" to set dislikeFlags to disliked of every track of library playlist 1 whose media kind is song
	end try
	try
		tell application "Music" to set enabledFlags to enabled of every track of library playlist 1 whose media kind is song
	end try
	if (count of skipCounts) is not n then set skipCounts to my filledList(n, 0)
	if (count of ratingList) is not n then set ratingList to my filledList(n, 0)
	if (count of favFlags) is not n then set favFlags to my filledList(n, false)
	if (count of dislikeFlags) is not n then set dislikeFlags to my filledList(n, false)
	if (count of enabledFlags) is not n then set enabledFlags to my filledList(n, true)
	
	-- Score every song. cIdx holds the library positions of eligible songs and
	-- cum their running total of weights (used for weighted sampling below).
	set nowDate to current date
	set sd to staleDays
	if sd < 1 then set sd to 1
	set staleSecs to sd * days
	set cutoff to nowDate - staleSecs
	set cIdx to {}
	set cum to {}
	set runningTotal to 0.0
	repeat with i from 1 to n
		set okFlag to true
		if (item i of enabledFlags) is false then set okFlag to false
		if (item i of dislikeFlags) is true then set okFlag to false
		if okFlag then
			set pc to item i of playCounts
			if pc is missing value then set pc to 0
			set sk to item i of skipCounts
			if sk is missing value then set sk to 0
			-- Skipped far more than played: you've already told Music you don't want it.
			if sk ≥ 3 and sk > pc then set okFlag to false
			-- When was it last "alive"? Last play, or the day it was added.
			if pc > 0 and (item i of playDates) is not missing value then
				set baseDate to item i of playDates
			else
				set baseDate to item i of addedDates
			end if
			if okFlag and baseDate is not missing value then
				if baseDate ≥ cutoff then set okFlag to false
			end if
		end if
		if okFlag then
			if pc is 0 then
				set w to 0.4
			else
				set capped to pc
				if capped > 10 then set capped to 10
				set w to 1 + capped * 0.5
			end if
			if (item i of favFlags) is true then set w to w * 3
			set rt to item i of ratingList
			if rt is not missing value then
				if rt ≥ 80 then
					set w to w * 2
				else if rt ≥ 1 and rt ≤ 40 then
					set w to w * 0.25
				end if
			end if
			set w to w / (1 + sk)
			if baseDate is not missing value then
				set dm to (nowDate - baseDate) / staleSecs
				if dm > 5 then set dm to 5
				set w to w * dm
			end if
			set runningTotal to runningTotal + w
			set end of cIdx to i
			set end of cum to runningTotal
		end if
	end repeat
	
	set m to count of cIdx
	if m is 0 then return {{}, {}, {}, 0, 0}
	set targetSize to my rediscoverTarget(n)
	set historyIDs to my loadRediscoverHistory()
	
	set picked to {}
	set pickedKeys to {}
	if m ≤ targetSize then
		-- Fewer candidates than slots: take them all.
		repeat with j from 1 to m
			set end of picked to j
		end repeat
	else
		-- Pass 1: weighted draw honoring the artist cap and cooldown history.
		set res to my samplePicks(cum, runningTotal, cIdx, libPIDs, libArtists, historyIDs, targetSize, picked, pickedKeys, true)
		set picked to item 1 of res
		set pickedKeys to item 2 of res
		-- Pass 2: still short (small pool)? Relax those rules instead of leaving it short.
		if (count of picked) < targetSize then
			set res to my samplePicks(cum, runningTotal, cIdx, libPIDs, libArtists, historyIDs, targetSize, picked, pickedKeys, false)
			set picked to item 1 of res
			set pickedKeys to item 2 of res
		end if
		-- Pass 3: last resort, fill from the front of the candidate list.
		if (count of picked) < targetSize then
			repeat with j from 1 to m
				if (count of picked) ≥ targetSize then exit repeat
				if not (picked contains j) then set end of picked to j
			end repeat
		end if
	end if
	
	set pickTracks to {}
	set pickArtists to {}
	set pickIDs to {}
	repeat with j in picked
		set libI to item (contents of j) of cIdx
		set end of pickTracks to item libI of libTracks
		set end of pickArtists to item libI of libArtists
		set end of pickIDs to item libI of libPIDs
	end repeat
	return {pickTracks, pickArtists, pickIDs, m, targetSize}
end findRediscoverPicks

-- A list of n copies of v.
on filledList(n, v)
	set outList to {}
	repeat with i from 1 to n
		set end of outList to v
	end repeat
	return outList
end filledList

-- Weighted random sampling without replacement. cum holds the running total of
-- the candidates' weights, so a random point in 0..total lands on a candidate in
-- proportion to its weight (found by binary search); repeats are skipped.
-- picked / pickedKeys (candidate positions / artist names) are extended until
-- targetSize is reached or the attempt limit runs out, and returned.
-- enforceRules: honor rediscoverMaxPerArtist and the cooldown history.
on samplePicks(cum, total, cIdx, libPIDs, libArtists, historyIDs, targetSize, picked, pickedKeys, enforceRules)
	set m to count of cum
	set attempts to 0
	set maxAttempts to targetSize * 40 + 200
	repeat while (count of picked) < targetSize and attempts < maxAttempts
		set attempts to attempts + 1
		set r to (random number) * total
		set lo to 1
		set hi to m
		repeat while lo < hi
			set mid to (lo + hi) div 2
			if (item mid of cum) < r then
				set lo to mid + 1
			else
				set hi to mid
			end if
		end repeat
		if not (picked contains lo) then
			set okPick to true
			set libI to item lo of cIdx
			set k to my artistKey(item libI of libArtists)
			if enforceRules then
				if historyIDs contains (item libI of libPIDs) then set okPick to false
				if okPick and rediscoverMaxPerArtist > 0 and k is not "" and (pickedKeys contains k) then
					set c to 0
					repeat with pk in pickedKeys
						if (contents of pk) is k then set c to c + 1
					end repeat
					if c ≥ rediscoverMaxPerArtist then set okPick to false
				end if
			end if
			if okPick then
				set end of picked to lo
				set end of pickedKeys to k
			end if
		end if
	end repeat
	return {picked, pickedKeys}
end samplePicks

-- How many songs SeTeR Rediscover should hold for a library of libCount songs:
-- rediscoverPercent % of the library, clamped to rediscoverMin..rediscoverMax.
on rediscoverTarget(libCount)
	set sz to round (libCount * rediscoverPercent / 100) rounding to nearest
	if sz < rediscoverMin then set sz to rediscoverMin
	if sz > rediscoverMax then set sz to rediscoverMax
	return sz
end rediscoverTarget

-- ---------------------------------------------------------------------------
-- REDISCOVER HISTORY (cooldown)
-- ---------------------------------------------------------------------------

on rediscoverHistoryPath()
	return (POSIX path of (path to documents folder)) & "SeTeRShuffle/rediscover-history.tsv"
end rediscoverHistoryPath

-- Persistent IDs Rediscover picked within the last rediscoverCooldownDays days.
-- The file holds one "YYYY-MM-DD<tab>ID" line per pick. Never throws: with no
-- history the worst case is a repeat song.
on loadRediscoverHistory()
	if rediscoverCooldownDays < 1 then return {}
	try
		set histPath to my rediscoverHistoryPath()
		set cutoffDay to do shell script "date -v-" & rediscoverCooldownDays & "d +%Y-%m-%d"
		set raw to do shell script "if [ -f " & quoted form of histPath & " ]; then awk -F'\\t' -v c=" & quoted form of cutoffDay & " '$1 >= c {print $2}' " & quoted form of histPath & "; fi"
		if raw is "" then return {}
		return paragraphs of raw
	on error errMsg
		my logLine("note: couldn't read Rediscover history (" & errMsg & ")")
		return {}
	end try
end loadRediscoverHistory

-- Remembers today's picks and drops entries older than the cooldown window.
-- Never throws: a history problem must not fail the refresh.
on saveRediscoverHistory(pickIDs)
	if rediscoverCooldownDays < 1 then return
	if (count of pickIDs) is 0 then return
	try
		set histPath to my rediscoverHistoryPath()
		set dayStr to do shell script "date +%Y-%m-%d"
		set cutoffDay to do shell script "date -v-" & rediscoverCooldownDays & "d +%Y-%m-%d"
		do shell script "mkdir -p " & quoted form of (POSIX path of (path to documents folder) & "SeTeRShuffle")
		set AppleScript's text item delimiters to linefeed
		set idText to pickIDs as text
		set AppleScript's text item delimiters to ""
		set cmd to "printf '%s\\n' " & quoted form of idText & " | awk -v d=" & quoted form of dayStr & " '{print d \"\\t\" $0}' >> " & quoted form of histPath
		do shell script cmd
		set cmd to "f=" & quoted form of histPath & "; awk -F'\\t' -v c=" & quoted form of cutoffDay & " '$1 >= c' \"$f\" > \"$f.tmp\" && mv \"$f.tmp\" \"$f\""
		do shell script cmd
	on error errMsg
		set AppleScript's text item delimiters to ""
		my logLine("note: couldn't save Rediscover history (" & errMsg & ")")
	end try
end saveRediscoverHistory

-- ---------------------------------------------------------------------------
-- BUILDING THE REDISCOVER PLAYLIST
-- ---------------------------------------------------------------------------

-- Picks, orders and returns {finalTracks, pickIDs, candidateCount, targetSize},
-- or missing value when nothing is eligible. Changes nothing in Music.
on prepareRediscover()
	set found to my findRediscoverPicks()
	set pickTracks to item 1 of found
	if (count of pickTracks) is 0 then return missing value
	set finalTracks to my shuffleTrackRefs(pickTracks, item 2 of found, true)
	return {finalTracks, item 3 of found, item 4 of found, item 5 of found}
end prepareRediscover

-- Rewrites "SeTeR Rediscover" with the given songs (created if missing, reused
-- otherwise so its artwork survives). Returns how many songs ended up in it.
on writeRediscoverPlaylist(finalTracks, pickIDs)
	tell application "Music"
		if exists playlist "SeTeR Rediscover" then
			set newPl to playlist "SeTeR Rediscover"
		else
			set newPl to make new user playlist with properties {name:"SeTeR Rediscover"}
		end if
	end tell
	set addedCount to my fillRediscoverPlaylist(newPl, finalTracks)
	my stampDescription(newPl, "Last refreshed: ")
	my saveRediscoverHistory(pickIDs)
	return addedCount
end writeRediscoverPlaylist

-- Like buildPlaylist, but tolerant: a song Music refuses to add (for example one
-- that is no longer available) is skipped and logged instead of failing the
-- whole refresh. The songs are staged in a temp playlist first, so Rediscover is
-- never left empty by a failed run. Returns the number of songs added.
on fillRediscoverPlaylist(destPl, trackRefs)
	my assertUserPlaylist(destPl)
	set libBefore to my librarySize()
	set addedCount to 0
	set failedCount to 0
	tell application "Music"
		try
			delete (every user playlist whose name is tempPlaylistName)
		end try
		set tempPl to make new user playlist with properties {name:tempPlaylistName}
		repeat with t in trackRefs
			try
				duplicate (contents of t) to tempPl
				set addedCount to addedCount + 1
			on error
				set failedCount to failedCount + 1
			end try
		end repeat
		if addedCount is 0 then
			delete tempPl
			error "None of the Rediscover songs could be added to the playlist."
		end if
		delete (every track of destPl whose media kind is song)
		repeat with t in (every track of tempPl)
			duplicate (contents of t) to destPl
		end repeat
		delete tempPl
		if not isDaily then reveal destPl
	end tell
	if failedCount > 0 then my logLine("rediscover: " & failedCount & " song(s) couldn't be added and were skipped")
	set libAfter to my librarySize()
	if libAfter < libBefore then
		my logLine("LIBRARY SHRANK during rewrite: " & libBefore & " -> " & libAfter & " tracks")
		error "Your library went from " & libBefore & " to " & libAfter & " tracks during this run. Stopped. Check ~/Documents/SeTeRShuffle/backups/ for the library manifest."
	end if
	return addedCount
end fillRediscoverPlaylist

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
	set prepared to my prepareRediscover()
	if prepared is missing value then
		display dialog "Nothing to rediscover — everything in your library was played or added recently." buttons {"OK"} default button "OK" with title "SeTeR Shuffle"
		return
	end if
	set addedCount to my writeRediscoverPlaylist(item 1 of prepared, item 2 of prepared)
	display notification "SeTeR Rediscover ready — " & addedCount & " songs." with title "SeTeR Shuffle"
end doRediscover

on doDailyRediscover()
	set prepared to my prepareRediscover()
	if prepared is missing value then
		my logLine("rediscover: nothing to rediscover")
		return
	end if
	set addedCount to my writeRediscoverPlaylist(item 1 of prepared, item 2 of prepared)
	my logLine("rediscover: updated (" & addedCount & " songs picked from " & (item 3 of prepared) & " candidates)")
	display notification "SeTeR Rediscover updated — " & addedCount & " songs." with title "SeTeR Shuffle"
end doDailyRediscover

-- Terminal-only dry run: osascript SeTeR-shuffle.applescript rediscover-preview
-- Shows what the next Rediscover would pick (first 25 songs, in playlist order)
-- without changing anything in Music or the history file.
on previewRediscover()
	set prepared to my prepareRediscover()
	if prepared is missing value then return "Nothing to rediscover: everything eligible was played or added recently."
	set finalTracks to item 1 of prepared
	set total to count of finalTracks
	set outLines to {"Rediscover preview: " & total & " songs picked from " & (item 3 of prepared) & " candidates (target " & (item 4 of prepared) & "). Nothing was changed.", ""}
	set shown to total
	if shown > 25 then set shown to 25
	repeat with i from 1 to shown
		set t to item i of finalTracks
		tell application "Music"
			set trackArtist to artist of t
			set trackName to name of t
		end tell
		set end of outLines to (i as text) & ". " & my safeText(trackArtist) & " - " & my safeText(trackName)
	end repeat
	if total > shown then set end of outLines to "... and " & (total - shown) & " more"
	set AppleScript's text item delimiters to linefeed
	set outText to outLines as text
	set AppleScript's text item delimiters to ""
	return outText
end previewRediscover
