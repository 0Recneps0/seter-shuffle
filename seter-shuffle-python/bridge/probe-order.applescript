-- RETIRED FROM BUILDS (2026-10-29). This script is now a standalone
-- manual sanity check ONLY (`./run.sh probe`). No build consults it:
-- a fresh 3-song playlist reported "forward" on 2026-10-28 while the
-- real sorted 806-song playlist still failed every build, and the
-- track `index` channel it relies on was killed as a manual-order
-- reference by the 2026-10-29 diagnostic (list read reversed against
-- the backup, yet the list's first track carries index 1). Builds
-- use bridge/sort-probe on a throwaway carrying the target's sort
-- instead. Do not wire this script back into a build path.
--
-- probe-order.applescript (SeTeR Shuffle, Python experimental core)
--
-- MEASURES, instead of guessing, which way Music orders a playlist on
-- this Mac. This exists because of the 2026-10-28 failure: the .4
-- bridge applied a shuffle to a real 806-song playlist, and apply,
-- its restore, and undo all failed exact-order verification in a
-- loop. The pre-undo snapshot pulled off that Mac was the EXACT
-- REVERSE of the original backup (806/806 same songs). Two mechanisms
-- explain that evidence equally well, and the backup files alone
-- cannot distinguish them:
--
--   (a) insert-reversed: `duplicate track to playlist` inserts at
--       the TOP of the playlist, so duplicating in order lands
--       reversed, while the every-track read is faithful.
--   (b) read-reversed: duplicating appends normally, but
--       `persistent ID of every track of playlist` returns tracks
--       in reverse playlist order, so the read is reversed while the
--       display is correct.
--
-- This probe tells them apart with TWO reads of the same probe
-- playlist, plus a positional cross-check:
--
--   * LIST:  persistent ID of every track of the probe playlist
--            (the read every other bridge script uses).
--   * INDEX: for each picked song, the `index` property of its
--            entry in the probe playlist, sorted ascending. The
--            index is the entry's position in the playlist, a
--            different property from the enumeration order, so it
--            is a second channel, not just the same read twice.
--   * POS:   persistent ID of track 1 and of the last track, read
--            by position.
--
-- Verdicts (picked order is P1, P2, P3):
--   forward:         LIST = P1,P2,P3 and INDEX = P1,P2,P3.
--   insert-reversed: LIST = P3,P2,P1 and INDEX = P3,P2,P1. The
--                    entries really are reversed: insertion put
--                    them at the top.
--   read-reversed:   LIST = P3,P2,P1 but INDEX = P1,P2,P3. The
--                    entries are in the picked order; only the
--                    enumeration read is reversed.
--   ambiguous:       anything else, or any read that fails, or a
--                    positional read that contradicts the model
--                    above. An ambiguous probe ABORTS the run in
--                    run.sh: the real playlist is never touched on
--                    an ambiguous result, because a wrong guess here
--                    is exactly the .4 bug.
--
-- HONEST LIMIT, read this before trusting the probe: the positional
-- read goes through the same Music scripting bridge as the list
-- read, so it is NOT an independent instrument. It is used only as
-- a contradiction check (if it disagrees with both other channels,
-- the probe is ambiguous). The two real channels are LIST and
-- INDEX. If even those agreed only because the bridge reverses
-- everything consistently, the probe would misclassify read-reversed
-- as insert-reversed or vice versa. That residual risk is why the
-- Mac procedure in BRIDGE-SAFETY.md also requires a manual eyeball
-- step: run this script with "keep", look at the probe playlist in
-- Music itself, and confirm the on-screen order matches the verdict
-- before any real playlist is ever built with a probed mode.
--
-- Safety:
--  * The probe touches exactly one playlist, which it creates itself
--    under a caller-supplied name (run.sh passes a timestamped name).
--    If a playlist with that name already exists, the probe refuses
--    rather than deleting something that might be the user's.
--  * It deletes its own probe playlist at the end, and also on any
--    error path, so a failed probe does not leave a stray playlist
--    behind (if deletion itself fails, the error says so loudly).
--  * It never deletes library tracks and never touches any other
--    playlist. It duplicates only the first 3 song tracks of the
--    library, and it refuses if the library has fewer than 3 songs.
--
-- Usage:
--   osascript probe-order.applescript [probe-playlist-name] [keep]
-- With "keep" as the second argument the probe playlist is LEFT in
-- place for the manual eyeball check; without it, it is deleted and
-- the output ends with PROBE_CLEANUP_OK. The output is a block of
-- PROBE_* lines; run.sh parses PROBE_VERDICT: and PROBE_CLEANUP_OK
-- from it, and treats any verdict other than the three modes as a
-- failed gate. A completed probe exits 0 even when ambiguous (so
-- its lines reach the log); only hard failures (cannot create the
-- probe playlist, fewer than 3 library songs, cleanup failure)
-- exit non-zero.
--
-- UNVERIFIED ON A MAC (see BRIDGE-SAFETY.md): every Music
-- interaction here, including whether the `index` property is
-- exposed on playlist tracks in this Music version. If it is not,
-- the probe reports ambiguous (fail-closed), never a guessed mode.

on run argv
	set probeName to "SeTeR Shuffle Probe"
	if (count of argv) > 0 then set probeName to item 1 of argv
	set keepProbe to false
	if (count of argv) > 1 and (item 2 of argv) is "keep" then set keepProbe to true
	if probeName is "" then
		error "probe: probe playlist name must not be empty." number 1
	end if
	set probePl to missing value
	try
		tell application "Music"
			set matches to every playlist whose name is probeName
		end tell
		if (count of matches) > 0 then
			error "probe: refusing: a playlist named \"" & probeName & "\" already exists; refusing to delete or reuse something that might be yours. Delete or rename it and re-run." number 1
		end if
		tell application "Music"
			set libSongs to every track of library playlist 1 whose media kind is song
		end tell
		if (count of libSongs) < 3 then
			error "probe: library has fewer than 3 songs; cannot probe playlist order." number 1
		end if
		set pickedTracks to {item 1 of libSongs, item 2 of libSongs, item 3 of libSongs}
		set pickedIDs to {}
		tell application "Music"
			repeat with t in pickedTracks
				set end of pickedIDs to persistent ID of (contents of t)
			end repeat
		end tell
		if (count of pickedIDs) is not 3 then
			error "probe: could not read 3 distinct library songs." number 1
		end if
		if (item 1 of pickedIDs) is (item 2 of pickedIDs) or (item 1 of pickedIDs) is (item 3 of pickedIDs) or (item 2 of pickedIDs) is (item 3 of pickedIDs) then
			error "probe: first 3 library songs are not distinct; cannot probe." number 1
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
		set indexOrder to my indexOrderFor(probePl, pickedIDs)
		set posEnds to my positionalEnds(probePl)
		set verdict to my verdictFor(pickedIDs, listIDs, indexOrder, posEnds)
		set outLines to {"PROBE_PICKED: " & my joinSpace(pickedIDs), "PROBE_LIST: " & my joinSpace(listIDs)}
		if indexOrder is missing value then
			set end of outLines to "PROBE_INDEX_ORDER: unavailable"
		else
			set end of outLines to "PROBE_INDEX_ORDER: " & my joinSpace(indexOrder)
		end if
		if posEnds is missing value then
			set end of outLines to "PROBE_POS_FIRST: unavailable"
			set end of outLines to "PROBE_POS_LAST: unavailable"
		else
			set end of outLines to "PROBE_POS_FIRST: " & (firstID of posEnds)
			set end of outLines to "PROBE_POS_LAST: " & (lastID of posEnds)
		end if
		set end of outLines to "PROBE_VERDICT: " & verdict
		if verdict is "ambiguous" then
			set end of outLines to "PROBE_REASON: list/index/positional reads do not fit any known model, or a read failed; do not build with a guessed direction."
		end if
		if keepProbe then
			set end of outLines to "PROBE_KEPT: probe playlist \"" & probeName & "\" left in place for the manual eyeball check; delete it in Music when done."
		else
			my deleteProbe(probePl)
			set end of outLines to "PROBE_CLEANUP_OK"
		end if
		set AppleScript's text item delimiters to linefeed
		set outText to outLines as text
		set AppleScript's text item delimiters to ""
		-- Deliberately RETURNED, not errored, even for "ambiguous":
		-- run.sh must see the PROBE_* lines in the log to know why
		-- the run aborted. run.sh treats any verdict other than the
		-- three modes as a failed gate and touches no real playlist.
		return outText
	on error errMsg number errNum
		if probePl is not missing value then
			try
				my deleteProbe(probePl)
			end try
		end if
		error errMsg number errNum
	end try
end run

on playlistIDs(pl)
	-- Same empty-playlist fallback as apply-order (2026-10-29,
	-- mode 34): a filtered bulk read can fail with -1728 on a
	-- brand-new playlist, so an unfiltered count of 0 returns {}
	-- instead of failing. This script is retired from builds and
	-- only ever reads a 3-song probe playlist, so the fallback
	-- never fires in practice; it is here for consistency, and
	-- a non-empty read failure still errors.
	try
		tell application "Music"
			return persistent ID of every track of pl whose media kind is song
		end tell
	on error
		try
			tell application "Music"
				if (count of tracks of pl) is 0 then return {}
			end tell
		end try
		error "probe: could not read the probe playlist's song IDs." number 1
	end try
end playlistIDs

on reverseList(a)
	set outList to {}
	repeat with i from (count of a) to 1 by -1
		set end of outList to item i of a
	end repeat
	return outList
end reverseList

on listsEqual(a, b)
	if (count of a) is not (count of b) then return false
	repeat with i from 1 to (count of a)
		if (item i of a) is not (item i of b) then return false
	end repeat
	return true
end listsEqual

-- The picked IDs ordered by their `index` property inside the probe
-- playlist. Returns missing value if any index read fails, or the
-- indices are not exactly 1..n (duplicated, missing, or out of
-- range): in any of those cases the index channel is unusable and
-- the probe must be ambiguous, not guessed.
on indexOrderFor(pl, pickedIDs)
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
end indexOrderFor

-- Positional first/last track IDs, or missing value if the probe
-- playlist does not hold exactly 3 song tracks (it must: the probe
-- created it with exactly 3 songs and nothing else).
on positionalEnds(pl)
	tell application "Music"
		set totalTracks to count of tracks of pl
		set songCount to count of (every track of pl whose media kind is song)
		if totalTracks is not songCount then return missing value
		if songCount is not 3 then return missing value
		set firstID to persistent ID of track 1 of pl
		set lastID to persistent ID of track 3 of pl
	end tell
	return {firstID:firstID, lastID:lastID}
end positionalEnds

-- Decide the verdict from the three channels. Positional ends are a
-- contradiction check only: they must match the model the other two
-- channels agree on, or the result is ambiguous. They are never used
-- alone to pick a direction, because they travel through the same
-- scripting bridge as the list read (see the header limit).
on verdictFor(pickedIDs, listIDs, indexOrder, posEnds)
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
end verdictFor

on joinSpace(idList)
	set AppleScript's text item delimiters to " "
	set t to idList as text
	set AppleScript's text item delimiters to ""
	return t
end joinSpace

on deleteProbe(pl)
	tell application "Music"
		delete pl
	end tell
end deleteProbe
