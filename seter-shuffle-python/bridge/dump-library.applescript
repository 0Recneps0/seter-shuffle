-- dump-library.applescript (SeTeR Shuffle, Python experimental core)
--
-- Dumps the Music library, or one playlist, to the JSON format the
-- Python core reads. READ-ONLY: it changes nothing in Music.
--
-- Usage:
--   osascript dump-library.applescript <output-json-path> [playlist-name]
-- With no playlist name, the whole library is dumped. With a name, only
-- that playlist's songs are dumped (used for shuffling one playlist).
--
-- Dates are written as ISO strings built from the date's own year /
-- month / day / time components (never from a locale date string, so
-- the output does not depend on the Mac's date format). Missing values
-- become JSON null for bpm / year / dates, and the v2.6 neutral
-- defaults for everything else (0 counts, false flags, enabled true).
--
-- UNVERIFIED ON A MAC (see README-PYTHON.md): bulk property reads for
-- bpm / year / played date / date added, `month as integer`, and the
-- date-component ISO formatting. The Python core was tested here; this
-- script was not, because this machine has no Music app or osascript.

on run argv
	if (count of argv) < 1 then
		error "dump-library.applescript: missing output path argument" number 1
	end if
	set outPath to item 1 of argv
	set playlistName to ""
	if (count of argv) > 1 then set playlistName to item 2 of argv

	tell application "Music"
		if playlistName is "" then
			set sourcePl to library playlist 1
		else
			if not (exists playlist playlistName) then
				error "dump-library: no playlist named \"" & playlistName & "\"" number 1
			end if
			set sourcePl to playlist playlistName
		end if
		set libPIDs to persistent ID of every track of sourcePl whose media kind is song
		set libNames to name of every track of sourcePl whose media kind is song
		set libArtists to artist of every track of sourcePl whose media kind is song
		set libAlbums to album of every track of sourcePl whose media kind is song
		set libGenres to genre of every track of sourcePl whose media kind is song
		set libPlayCounts to played count of every track of sourcePl whose media kind is song
		set libPlayDates to played date of every track of sourcePl whose media kind is song
		set libAddedDates to date added of every track of sourcePl whose media kind is song
	end tell
	set n to count of libPIDs

	-- Optional signals: any Music cannot provide falls back to neutral.
	set libBPMs to my bulkOrDefault("bpm", sourcePl, n, missing value)
	set libYears to my bulkOrDefault("year", sourcePl, n, missing value)
	set libSkipCounts to my bulkOrDefault("skipped count", sourcePl, n, 0)
	set libRatings to my bulkOrDefault("rating", sourcePl, n, 0)
	set libFavFlags to my bulkOrDefault("favorited", sourcePl, n, false)
	if (count of libFavFlags) is not n then
		set libFavFlags to my bulkOrDefault("loved", sourcePl, n, false)
	end if
	set libDislikeFlags to my bulkOrDefault("disliked", sourcePl, n, false)
	set libEnabledFlags to my bulkOrDefault("enabled", sourcePl, n, true)

	set outLines to {"{\"tracks\": ["}
	repeat with i from 1 to n
		set pidText to my jsonText(item i of libPIDs)
		set nameText to my jsonText(my safeText(item i of libNames))
		set artistText to my jsonText(my safeText(item i of libArtists))
		set albumText to my jsonText(my safeText(item i of libAlbums))
		set genreText to my jsonText(my safeText(item i of libGenres))
		set bpmText to my jsonNumber(item i of libBPMs)
		set yearText to my jsonNumber(item i of libYears)
		set pcText to my jsonInt(item i of libPlayCounts, 0)
		set skText to my jsonInt(item i of libSkipCounts, 0)
		set rtText to my jsonInt(item i of libRatings, 0)
		set favText to my jsonBool(item i of libFavFlags, false)
		set disText to my jsonBool(item i of libDislikeFlags, false)
		set enText to my jsonBool(item i of libEnabledFlags, true)
		set playedText to my jsonDate(item i of libPlayDates)
		set addedText to my jsonDate(item i of libAddedDates)
		set lineText to "  {\"persistent_id\": " & pidText & ", \"name\": " & nameText & ", \"artist\": " & artistText & ", \"album\": " & albumText & ", \"genre\": " & genreText & ", \"bpm\": " & bpmText & ", \"year\": " & yearText & ", \"played_count\": " & pcText & ", \"skipped_count\": " & skText & ", \"rating\": " & rtText & ", \"favorited\": " & favText & ", \"disliked\": " & disText & ", \"enabled\": " & enText & ", \"played_date\": " & playedText & ", \"date_added\": " & addedText & "}"
		if i < n then set lineText to lineText & ","
		set end of outLines to lineText
	end repeat
	set end of outLines to "]}"

	set AppleScript's text item delimiters to linefeed
	set fileText to outLines as text
	set AppleScript's text item delimiters to ""
	set fh to open for access (POSIX file outPath) with write permission
	try
		set eof of fh to 0
		write fileText to fh as «class utf8»
		close access fh
	on error errMsg number errNum
		try
			close access fh
		end try
		error "dump-library: could not write " & outPath & ": " & errMsg number errNum
	end try
	return "dumped " & n & " songs to " & outPath
end run

-- One bulk property read, with a neutral fallback list if Music cannot
-- provide it. propName is passed as text and evaluated through a tell
-- block per property name; AppleScript cannot indirect a property by
-- string, so each known property has its own branch below.
on bulkOrDefault(propName, sourcePl, n, defaultVal)
	set vals to {}
	try
		tell application "Music"
			if propName is "bpm" then
				set vals to bpm of every track of sourcePl whose media kind is song
			else if propName is "year" then
				set vals to year of every track of sourcePl whose media kind is song
			else if propName is "skipped count" then
				set vals to skipped count of every track of sourcePl whose media kind is song
			else if propName is "rating" then
				set vals to rating of every track of sourcePl whose media kind is song
			else if propName is "favorited" then
				set vals to favorited of every track of sourcePl whose media kind is song
			else if propName is "loved" then
				set vals to loved of every track of sourcePl whose media kind is song
			else if propName is "disliked" then
				set vals to disliked of every track of sourcePl whose media kind is song
			else if propName is "enabled" then
				set vals to enabled of every track of sourcePl whose media kind is song
			end if
		end tell
	end try
	if (count of vals) is not n then
		set vals to {}
		repeat n times
			set end of vals to defaultVal
		end repeat
	end if
	return vals
end bulkOrDefault

on safeText(x)
	if x is missing value then return ""
	return x as text
end safeText

on jsonText(s)
	return "\"" & my jsonEscape(s) & "\""
end jsonText

on jsonEscape(s)
	set AppleScript's text item delimiters to "\\"
	set parts to text items of s
	set AppleScript's text item delimiters to "\\\\"
	set s to parts as text
	set AppleScript's text item delimiters to "\""
	set parts to text items of s
	set AppleScript's text item delimiters to "\\\""
	set s to parts as text
	set AppleScript's text item delimiters to linefeed
	set parts to text items of s
	set AppleScript's text item delimiters to "\\n"
	set s to parts as text
	set AppleScript's text item delimiters to return
	set parts to text items of s
	set AppleScript's text item delimiters to "\\r"
	set s to parts as text
	set AppleScript's text item delimiters to tab
	set parts to text items of s
	set AppleScript's text item delimiters to "\\t"
	set s to parts as text
	set AppleScript's text item delimiters to ""
	return s
end jsonEscape

on jsonNumber(x)
	if x is missing value then return "null"
	return x as text
end jsonNumber

on jsonInt(x, defaultVal)
	if x is missing value then return defaultVal as text
	return (x as integer) as text
end jsonInt

on jsonBool(x, defaultVal)
	if x is missing value then
		if defaultVal then return "true"
		return "false"
	end if
	if x then return "true"
	return "false"
end jsonBool

on pad2(n)
	if n < 10 then return "0" & (n as text)
	return n as text
end pad2

-- ISO date from components only; no locale date strings are involved.
on jsonDate(d)
	if d is missing value then return "null"
	set y to year of d
	set mo to (month of d) as integer
	set dy to day of d
	set secs to time of d
	set hh to secs div 3600
	set mm to (secs mod 3600) div 60
	set ss to secs mod 60
	return "\"" & y & "-" & my pad2(mo) & "-" & my pad2(dy) & "T" & my pad2(hh) & ":" & my pad2(mm) & ":" & my pad2(ss) & "Z\""
end jsonDate
