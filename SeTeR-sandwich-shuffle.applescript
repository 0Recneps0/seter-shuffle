-- SeTeR Sandwich Shuffle — one-click run of the daily refresh: reshuffles
-- "my new sandwich recipe" in place AND updates "Void Rediscover".
-- Export as Application from Script Editor for a double-clickable app
-- (File > Export > File Format: Application).
-- Needs SeTeR-shuffle.applescript (v2.3+) saved at ~/Documents/SeTeRShuffle/.
-- To undo a shuffle, open the SeTeR Shuffle app and choose "Undo last shuffle".

property playlistName : "my new sandwich recipe"
property scriptRelPath : "SeTeRShuffle/SeTeR-shuffle.applescript"
property logPath : "$HOME/Library/Logs/seter-shuffle.log"

on run
	set scriptPath to (POSIX path of (path to documents folder)) & scriptRelPath
	
	-- Friendly message instead of a cryptic shell error if the script is missing.
	try
		do shell script "test -f " & quoted form of scriptPath
	on error
		display dialog "Couldn't find SeTeR-shuffle.applescript at:" & return & scriptPath & return & return & "Save SeTeR Shuffle v2.3 or newer there and try again." buttons {"OK"} default button "OK" with icon stop with title "SeTeR Sandwich Shuffle"
		return
	end try
	
	display notification "Reshuffling “" & playlistName & "” and refreshing Void Rediscover…" with title "SeTeR Sandwich Shuffle"
	
	try
		-- Large playlists can take minutes; don't let the default AppleEvent timeout cut it off.
		with timeout of 3600 seconds
			do shell script "/usr/bin/osascript " & quoted form of scriptPath & " daily " & quoted form of playlistName
		end timeout
	on error errMsg
		if (length of errMsg) > 400 then set errMsg to (text 1 thru 400 of errMsg) & "…"
		set answer to display dialog "The daily refresh hit a problem:" & return & return & errMsg & return & return & "Details are in ~/Library/Logs/seter-shuffle.log. If a playlist looks wrong, open SeTeR Shuffle and choose “Undo last shuffle”." buttons {"Open Log", "OK"} default button "OK" with icon caution with title "SeTeR Sandwich Shuffle"
		if button returned of answer is "Open Log" then
			try
			do shell script "open \"" & logPath & "\""
			end try
		end if
		return
	end try
	
	-- Success: show the last couple of log lines (timestamps stripped).
	try
		set summary to do shell script "tail -n 2 \"" & logPath & "\" | cut -c21-"
		display notification summary with title "SeTeR Sandwich Shuffle — done"
	end try
end run