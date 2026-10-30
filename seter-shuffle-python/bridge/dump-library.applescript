-- dump-library.applescript (SeTeR Shuffle, Python experimental core)
--
-- SAFETY NOTES (this script is read-only, but a bad dump is still a
-- safety problem, because everything downstream trusts it):
--  * READ-ONLY: this script never deletes, creates, duplicates, or
--    otherwise modifies anything in Music. It only reads properties
--    and writes one JSON file. The only write is the output file.
--  * A playlist name is resolved by a filtered lookup, never by a
--    bare name reference: zero matches is an error, more than one
--    match is refused as ambiguous, exactly one is used. A dump of
--    the wrong playlist would otherwise silently feed the wrong
--    songs into an order.
--  * After the bulk reads, every required list must have exactly as
--    many entries as the PID list. A shorter or longer list means
--    the library changed mid-read or a read failed partway, and
--    the per-track values would be misaligned. That aborts before
--    anything is written: a misaligned dump is worse than no dump.
--  * Optional properties (bpm, year, skips, rating, favorited,
--    disliked, enabled) use a bulk read that returns "missing" on
--    any failure instead of silently padding: if the whole read
--    fails, every track gets the neutral default, never another
--    track's value. The favorited -> loved fallback actually runs
--    now (in the old script it could not: the old helper always
--    padded to full length, so its "count is not n" check never
--    fired and loved was never tried).
--  * The output is written to a temporary file and atomically
--    renamed into place, so a failed write can never leave a
--    half-written dump at the output path for the next step to
--    mistake for a complete one. The runner also works in a fresh
--    temporary directory per run, and the Python core refuses to
--    load malformed JSON, duplicate persistent IDs, or a non-list
--    tracks value, so a bad dump still fails closed before any
--    playlist write.
--  * JSON escaping handles backslash, quote, newline, carriage
--    return, tab, and every other control character (as \u00XX), so
--    an exotic control character in a track name cannot make the
--    JSON unparseable. Non-ASCII characters pass through as UTF-8,
--    which JSON allows and the Python core reads.
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
-- UNVERIFIED ON A MAC (see BRIDGE-SAFETY.md): bulk property reads for
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
			set matches to every playlist whose name is playlistName
			if (count of matches) is 0 then
				error "dump-library: no playlist named \"" & playlistName & "\"" number 1
			else if (count of matches) > 1 then
				error "dump-library: refusing: " & (count of matches) & " playlists are named \"" & playlistName & "\"; refusing to guess which one you mean. Rename one of them and re-run." number 1
			else
				set sourcePl to item 1 of matches
			end if
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

	-- Required lists must all line up with the PID list. If the
	-- library changed mid-read, per-track values would be misaligned
	-- (one song's name on another song's row), so abort unwritten.
	if (count of libNames) is not n or (count of libArtists) is not n or (count of libAlbums) is not n or (count of libGenres) is not n or (count of libPlayCounts) is not n or (count of libPlayDates) is not n or (count of libAddedDates) is not n then
		error "dump-library: bulk reads do not line up (PID list has " & n & " entries but another list differs); the library may have changed mid-read. Nothing was written; re-run." number 1
	end if

	-- Optional signals: a failed bulk read yields missing values for
	-- the whole list (neutral defaults below), never another track's
	-- value, and the favorited -> loved fallback now actually runs.
	set libBPMs to my bulkListOrMissing("bpm", sourcePl, n)
	if libBPMs is missing value then
		set libBPMs to my repeatValue(n, missing value)
	end if
	set libYears to my bulkListOrMissing("year", sourcePl, n)
	if libYears is missing value then
		set libYears to my repeatValue(n, missing value)
	end if
	set libSkipCounts to my bulkListOrMissing("skipped count", sourcePl, n)
	if libSkipCounts is missing value then
		set libSkipCounts to my repeatValue(n, 0)
	end if
	set libRatings to my bulkListOrMissing("rating", sourcePl, n)
	if libRatings is missing value then
		set libRatings to my repeatValue(n, 0)
	end if
	set libFavFlags to my bulkListOrMissing("favorited", sourcePl, n)
	if libFavFlags is missing value then
		set libFavFlags to my bulkListOrMissing("loved", sourcePl, n)
	end if
	if libFavFlags is missing value then
		set libFavFlags to my repeatValue(n, false)
	end if
	set libDislikeFlags to my bulkListOrMissing("disliked", sourcePl, n)
	if libDislikeFlags is missing value then
		set libDislikeFlags to my repeatValue(n, false)
	end if
	set libEnabledFlags to my bulkListOrMissing("enabled", sourcePl, n)
	if libEnabledFlags is missing value then
		set libEnabledFlags to my repeatValue(n, true)
	end if

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
	-- Atomic write: temp file, then rename into place, so a failed
	-- write can never leave a half-written dump at the output path.
	set tmpPath to outPath & ".tmp"
	set fh to open for access (POSIX file tmpPath) with write permission
	try
		set eof of fh to 0
		write fileText to fh as «class utf8»
		close access fh
	on error errMsg number errNum
		try
			close access fh
		end try
		try
			do shell script "rm -f " & quoted form of tmpPath
		end try
		error "dump-library: could not write " & outPath & ": " & errMsg number errNum
	end try
	try
		do shell script "mv -f " & quoted form of tmpPath & " " & quoted form of outPath
	on error errMsg
		try
			do shell script "rm -f " & quoted form of tmpPath
		end try
		error "dump-library: could not install dump at " & outPath & ": " & errMsg number 1
	end try
	try
		do shell script "test -s " & quoted form of outPath
	on error
		error "dump-library: dump file at " & outPath & " is empty after writing; refusing to hand a bad dump downstream." number 1
	end try
	return "dumped " & n & " songs to " & outPath
end run

-- One bulk property read. Returns the value list, or missing value
-- if the read fails or returns the wrong number of entries. The
-- caller then fills neutral defaults for the whole list. Returning
-- missing value (instead of padding) is what makes fallbacks like
-- favorited -> loved actually work, and guarantees a partial read
-- can never misalign values onto the wrong tracks.
-- propName is passed as text and evaluated through a tell block per
-- property name; AppleScript cannot indirect a property by string,
-- so each known property has its own branch below.
on bulkListOrMissing(propName, sourcePl, n)
	set vals to missing value
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
	if vals is missing value then return missing value
	if (count of vals) is not n then return missing value
	return vals
end bulkListOrMissing

on repeatValue(n, val)
	set vals to {}
	repeat n times
		set end of vals to val
	end repeat
	return vals
end repeatValue

on safeText(x)
	if x is missing value then return ""
	return x as text
end safeText

on jsonText(s)
	return "\"" & my jsonEscape(s) & "\""
end jsonText

-- Character-by-character escape: backslash, quote, and the control
-- characters get JSON escapes; everything else passes through
-- unchanged (UTF-8 output, so non-ASCII names are fine). The old
-- version handled only five escapes and left any other control
-- character raw, which made the JSON unparseable and stopped the
-- run fail-closed; this version cannot do that. Written as a loop
-- over characters rather than text-item splits so no control
-- character can slip through a delimiter the split did not name.
on jsonEscape(s)
	set outText to ""
	set hexDigits to "0123456789abcdef"
	repeat with ch in s
		set c to contents of ch
		if c is "\\" then
			set outText to outText & "\\\\"
		else if c is "\"" then
			set outText to outText & "\\\""
		else if c is linefeed then
			set outText to outText & "\\n"
		else if c is return then
			set outText to outText & "\\r"
		else if c is tab then
			set outText to outText & "\\t"
		else if (id of c) < 32 then
			set codeNum to id of c
			set hiChar to character ((codeNum div 16) + 1) of hexDigits
			set loChar to character ((codeNum mod 16) + 1) of hexDigits
			set outText to outText & "\\u00" & hiChar & loChar
		else
			set outText to outText & c
		end if
	end repeat
	return outText
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
