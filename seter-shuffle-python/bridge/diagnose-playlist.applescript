-- diagnose-playlist.applescript: READ-ONLY diagnostic. Changes nothing.
--
-- Prints, for one named playlist: the song count, the first and last
-- persistent IDs as returned by the every-track list (the read every
-- bridge script uses), the first and last IDs read by position
-- (track 1 / last track), and the index property of the list's
-- first track. Comparing these lines against a backup file tells
-- whether the playlist's list-read state is the backup order, its
-- exact reverse, or something else, and whether the positional read
-- agrees with the list read.
--
-- INDEX IS NOT A MANUAL-ORDER REFERENCE, DO NOT USE IT AS ONE. On
-- 2026-10-29 the real playlist's list read was the exact reverse
-- of its original backup, yet its first list track carried index
-- 1. If index were manual order and the list were sorted
-- descending (reverse of manual), that track would carry the LAST
-- index, not 1. So index either follows the current view or the
-- manual order itself is the reversed list; either way it cannot
-- classify a sort. It is printed here as a reported value only.
-- Sort classification comes from bridge/sort-probe on a throwaway
-- carrying the target's sort, never from index.
--
-- Usage:
--   osascript diagnose-playlist.applescript "Playlist Name"
-- Safe to run on a real playlist: it never deletes, duplicates, or
-- creates anything, and it never touches the library.

on run argv
	if (count of argv) < 1 then
		error "diagnose: usage: <playlist-name>" number 1
	end if
	set playlistName to item 1 of argv
	if playlistName is "" then
		error "diagnose: playlist name must not be empty." number 1
	end if
	tell application "Music"
		set matches to every playlist whose name is playlistName
	end tell
	if (count of matches) is 0 then
		error "diagnose: no playlist named \"" & playlistName & "\"." number 1
	else if (count of matches) > 1 then
		error "diagnose: refusing: " & (count of matches) & " playlists are named \"" & playlistName & "\"; refusing to guess which one you mean." number 1
	end if
	set pl to item 1 of matches
	set outLines to {}
	tell application "Music"
		set totalTracks to count of tracks of pl
		set songIDs to persistent ID of every track of pl whose media kind is song
	end tell
	set songCount to count of songIDs
	set end of outLines to "COUNT_SONGS: " & songCount
	set end of outLines to "COUNT_TRACKS: " & totalTracks
	if songCount is 0 then
		set end of outLines to "LIST_FIRST: (empty)"
		set end of outLines to "LIST_LAST: (empty)"
	else
		set end of outLines to "LIST_FIRST: " & item 1 of songIDs
		set end of outLines to "LIST_LAST: " & item -1 of songIDs
	end if
	tell application "Music"
		try
			set posFirst to persistent ID of track 1 of pl
		on error
			set posFirst to "(unreadable)"
		end try
		try
			set posLast to persistent ID of track totalTracks of pl
		on error
			set posLast to "(unreadable)"
		end try
	end tell
	set end of outLines to "POS_FIRST: " & posFirst
	set end of outLines to "POS_LAST: " & posLast
	if songCount > 0 then
		tell application "Music"
			try
				set idxFirst to index of (first track of pl whose persistent ID is item 1 of songIDs)
				set end of outLines to "INDEX_OF_LIST_FIRST: " & idxFirst
			on error
				set end of outLines to "INDEX_OF_LIST_FIRST: unavailable"
			end try
		end tell
	end if
	set AppleScript's text item delimiters to linefeed
	set outText to outLines as text
	set AppleScript's text item delimiters to ""
	return outText
end run
