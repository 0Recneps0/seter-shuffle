-- list-playlists.applescript (SeTeR Shuffle, Python core, v3.0.10)
--
-- READ-ONLY: this script never deletes, creates, duplicates, or
-- otherwise modifies anything in Music. It only reads the names
-- of the user's playlists and prints one name per line, so the
-- Terminal menu can offer a numbered pick list instead of
-- requiring a typed playlist name. A playlist name that itself
-- contains a line break will print as two lines; the menu
-- picker then treats those as separate entries, which is a
-- display quirk only: picking the wrong line still goes
-- through every normal gate (mapping, dump, verify) for the
-- name that was picked, and 0 always falls back to typing
-- the exact name.
--
-- Usage:
--   osascript list-playlists.applescript
--
-- UNVERIFIED ON A MAC: this machine has no Music app or
-- osascript, so the script itself is unproven here; the menu
-- picker falls back to typing a name if this script fails or
-- prints nothing, so a failure here can never block the menu.

on run argv
	tell application "Music"
		set plNames to name of every user playlist
	end tell
	set outText to ""
	repeat with n in plNames
		if outText is "" then
			set outText to n
		else
			set outText to outText & linefeed & n
		end if
	end repeat
	return outText
end run
