# SeTeR Shuffle, Python core (v3.0.11)

This tree is the v3.0.11 experimental tree: Claude's v3.0.11
candidate (bug fixes + optional AI tagging) merged 2026-11-20
into the 2026-11-19 experimental staging. The v2.6
AppleScript build on main is not edited by this tree; it is only
disabled, by an explicit migration step, when the user runs the
one-click installer below.

## One-click install or update (v3.0.11)

Download the stable zip, unzip it, double-click
`SeTeR-Shuffle-Install.command` (or run `bash install-or-update.sh`),
and answer yes once. That one confirmation installs or updates
`~/Documents/SeTeRShufflePython` to v3.0.11, writes and loads the
8:00 AM `com.seter.python.daily` plist, and switches the daily
job from v2.6 to Python (migration), unless v2.6 is already
disabled. Backups, logs, and Rediscover history are kept; the
v2.6 script and backups are never deleted or edited; rollback
is `bash ~/Documents/SeTeRShufflePython/migrate-to-python.sh --rollback`.

EXPERIMENTAL 2026-11-20: Claude's v3.0.11 candidate merged into the experimental line
(not stable, not installed anywhere, on top of the 2026-11-19
experimental staging). What it adds: a real time-skew fix (the
dump writes local wall-clock time labelled Z, so every age was off
by 7-8 hours; "now" is now measured in the same frame), a
single-run lock for run.sh and daily.sh (a second run is refused
with exit 3 instead of interleaving with the first), an optional
probe cadence (SETER_PROBE_MAX_AGE_HOURS skips a self-probe while
the mapping is fresh), optional AI tagging for Flow through macOS
`fm` (off by default; on-device, fail-soft, cached), an optional
--split-collabs artist rule (off by default), and local-date
Rediscover history. Three of its fixes already existed in the
experimental line (artist case keys, artist-key whitespace trim,
Rediscover weight-ordered fill); the merge keeps the stricter
implementation of each (NFKC + casefold comparison keys, the
weight-ordered fill pinned by the experimental fill test). Version
is 3.0.11 throughout, so an install stamps itself 3.0.11, not
3.0.10. Nothing here has run on a Mac yet: the lock, the probe
cadence, and the `fm` self-test are all unproven on real hardware,
and the AI path needs `sudo fm license` once before first use.

EXPERIMENTAL 2026-11-19: Shuffle repair scans for a fixing swap when random tries miss it
(not stable, not installed anywhere, on top of the 2026-11-18
experimental staging). The repair pass fixes a same-artist clash by
swapping the clashing song with a random partner, but with 30 tries
over a big list a rare good partner is usually never drawn, so the
pass gave up on clashes a single swap would have fixed: one artist
on 45 of 100 songs left 1.60 clashes on average. When the random
tries fail now, the pass scans partners in order and takes the first
swap that reduces the local clash count, on its own 5,000-evaluation
budget so it cannot starve later clashes: that pool comes back 1.12
average (zero-clash runs 9 to 15 of 40), and a 846-song pool with one
artist on 300 comes back 77.1 to 74.8. Same-artist partners are still
skipped, the output is still a permutation of the same songs, and the
pass is still best effort. Mac spot check if he wants it: run the
tests inside the unzipped experimental tree (`python3 -m unittest
discover -s tests -q`), which prints only and changes nothing; do not
run `./run.sh shuffle` on a real playlist to see it, that rebuilds
the playlist. Still unproven on a Mac until a real shuffle runs
through it. Nothing else in this build changes: only shuffle.py, one
new test file, and one updated expectation in
test_spread_same_key_skip.py were touched, no bridge, run.sh,
daily.sh, cli.py, or installer file.

EXPERIMENTAL 2026-11-18: Rediscover's never-played songs start at the played-song base
(not stable, not installed anywhere, on top of the 2026-11-17
experimental staging). A never-played song added long ago is the most
forgotten song possible, but the old 0.4 base capped it at 2.0 against
a 10-play song's 30.0, a 15:1 ratio no amount of forgottenness could
close: in an even 50/50 pool never-played songs took 47 of 600 picks
(7.8%) over 20 seeds. The base is now 1.0, the same base every played
song starts from, so the plays tier (not a 60% unplayed discount) is
what separates played from unplayed: a never-played song tops out at
5.0, still below a once-played song's 7.5 at the same forgottenness.
Measured live here after the change: the same even pools come back
105 of 600 (17.5%) against 10-play songs and 251 of 600 (41.8%)
against once-played songs. No eligibility, history, cap, or ordering
rule changes, and favorited/rated/skip boosts still multiply the base
exactly as before. Mac spot check if he wants it: run the tests
inside the unzipped experimental tree (`python3 -m unittest discover
-s tests -q`), which prints only and changes nothing; do not run
`./run.sh rediscover` on a real playlist to see it, that rebuilds the
Rediscover playlist and records history. Still unproven on a Mac until
a real Rediscover runs through it. Nothing else in this build changes:
only rediscover.py, one new test file, and one updated expectation in
test_core.py were touched, no bridge, run.sh, daily.sh, cli.py, or
installer file.

EXPERIMENTAL 2026-11-17: Flow's greedy walk stops stranding hot songs at the end
(not stable, not installed anywhere, on top of the 2026-11-16
experimental staging). On the fall the walk could spend a slot on a
cold song that fits a later target perfectly, leaving a hot song with
no target left to land on, so the playlist ended on that hot song
after the cold tail: a 7-song pool [40, 44, 56, 69, 72, 87, 91] came
back [44, 56, 72, 91, 69, 40, 87], ending on the 87. The walk now
checks each slot for a stranded song, one that fits this slot clearly
better than any later slot and fits no later slot well (best later
fit at least 20 off, and at least 10 worse than its fit now), and
picks it now, so the fall keeps falling. Over 2,000 random pools the
rule improves the total arc error in 445 pools, worsens it in none,
and cuts playlists ending 20+ hotter than they start from 811 to
488 (the rest have no cold tail at all). Dense pools are untouched,
artist spacing still beats it, and it uses the rescaled targets under
the relative arc too. Mac spot check if he wants it: run the tests
inside the unzipped experimental tree (`python3 -m unittest discover
-s tests -q`), which prints only and changes nothing; do not run
`./run.sh flow` on a real playlist to see it, that rebuilds the Flow
playlist. Still unproven on a Mac until a real Flow runs through it.
Nothing else in this build changes: only flow.py, one new test file,
and one updated expectation in the relative-arc test were touched, no
bridge, run.sh, daily.sh, cli.py, or installer file.

EXPERIMENTAL 2026-11-16: Rediscover's last-resort fill takes the highest-weight songs left
(not stable, not installed anywhere, on top of the 2026-11-15
experimental staging). When the staged sampling passes cannot fill the
Rediscover target, the fill took the front of the candidate list in
library order, so a weak song sitting early in the dump could take a
slot over a stronger song sitting later. Verified live here with a
rigged draw stream that starves sampling: a 6-song pool with weights
rising down the library order came back with the 7.5-weight song
instead of the 20-weight one. The fill now takes the highest-weight
unpicked candidates, ties keeping library order, so an equal-weight
pool fills exactly as before; the sampling passes are untouched. Mac
spot check if he wants it: run the tests inside the unzipped
experimental tree (`python3 -m unittest discover -s tests -q`), which
prints only and changes nothing; do not run `./run.sh rediscover` on a
real playlist to see it, that rebuilds the Rediscover playlist and
records history. Still unproven on a Mac until a real Rediscover runs
through it. Nothing else in this build changes: only rediscover.py,
one new test file, and one docstring line in the staged-relaxation
test were touched, no bridge, run.sh, daily.sh, cli.py, or installer
file.

EXPERIMENTAL 2026-11-15: `record-history` prints a confirmation
(not stable, not installed anywhere, on top of the 2026-11-14
experimental staging). Every other daily step leaves a trace in the
run log, but record-history appended the picked IDs to the cooldown
history file and printed nothing, so the log had no visible proof the
cooldown was recorded after a successful Rediscover apply, and an empty
IDs file passed through just as silently. It now prints one line:
"History recorded: N IDs appended to <history file> (cooldown 14
days).", with honest variants for an empty IDs file and for a cooldown
under 1 day. It is print-only, the history rule and file content are
unchanged, and run.sh already tees this step's stdout into the run log.
Mac spot check if he wants it: run the tests inside the unzipped
experimental tree (`python3 -m unittest discover -s tests -q`), which
prints only and changes nothing; do not run `./run.sh rediscover` on a
real playlist to see it, that rebuilds the Rediscover playlist and
records history. Still unproven on a Mac until a real Rediscover runs
through it. Nothing else in this build changes: only cli.py,
rediscover.py (now returns the appended count), and one new test file
were touched, no bridge, run.sh, daily.sh, or installer file.

EXPERIMENTAL 2026-11-14: the real `rediscover` command prints the pick summary
(not stable, not installed anywhere, on top of the 2026-11-13
experimental staging). rediscover-preview has printed the "Rediscover picks:
N songs, X never played, Y favorited, Z rated 4-5 stars, forgotten A..B days,
max C per artist." line since 2026-11-07, but the real `rediscover` command
printed only the first 25 picks, so the daily run log hid what the applied
picks were actually made of: how much was never played, how much was
favorited or highly rated, how long the picks were forgotten, and whether one
artist dominates the list. It now prints the same line after the preview list,
inside the existing non-quiet output. It is print-only, describes picks
already computed, and changes no playlist and no file; --quiet still prints
nothing. Mac spot check if he wants it: run the tests inside the unzipped
experimental tree (`python3 -m unittest discover -s tests -q`), which prints
only and changes nothing; do not run `./run.sh rediscover` on a real playlist
to see it, that rebuilds the Rediscover playlist and records history. Still
unproven on a Mac until a real Rediscover runs through it. Nothing else in
this build changes: only cli.py, rediscover.py (docstring), and one existing
test file were touched, no bridge, run.sh, daily.sh, or installer file.

EXPERIMENTAL 2026-11-13: the real `flow` command prints the arc summary
(not stable, not installed anywhere, on top of the 2026-11-12
experimental staging). flowPreview has printed the "Flow arc: N songs,
energies lo..hi, starts A, peaks P at #K, ends B." line since 2026-11-02,
but the real `flow` command printed only the first 25 songs, so the daily
run log hid whether the applied order actually rose and fell: a flat first
page, or a pool that cannot fall after the peak, showed nothing about the
full order. It now prints the same line after the preview list, inside the
existing non-quiet output. It is print-only, describes an order already
computed, and changes no playlist and no file; --quiet still prints
nothing. Mac spot check if he wants it: run the tests inside the unzipped
experimental tree (`python3 -m unittest discover -s tests -q`), which
prints only and changes nothing; do not run `./run.sh flow` on a real
playlist to see it, that rebuilds the Flow playlist. Still unproven on a
Mac until a real Flow runs through it. Nothing else in this build changes:
only cli.py and one existing test file were touched, no bridge, run.sh,
daily.sh, or installer file.

EXPERIMENTAL 2026-11-12: shuffle prints a full-list spacing summary
(not stable, not installed anywhere, on top of the 2026-11-11
experimental staging). shuffle used to print only the first 25 songs,
so the first page hid whether the full order actually held its artist
spacing: the repair pass is best effort, and when one artist dominates
the list clashes remain with nothing in the output saying so. It now
prints one extra line after the preview list covering the whole order:
"Shuffle: N songs, X artists, C same-artist clashes within spacing S,
max M by one artist." The clash count uses the same rule the repair
pass uses, and the summary describes an order already computed, so it
changes no playlist and no file. Mac spot check if he wants it: run
the tests inside the unzipped experimental tree (`python3 -m unittest
discover -s tests -q`), which prints only and changes nothing; do not
run `./run.sh shuffle` on a real playlist to see it, that shuffles the
playlist. Still unproven on a Mac until a real shuffle runs through
it. Nothing else in this build changes: only shuffle.py, cli.py, and
one new test file were touched, no bridge, run.sh, daily.sh, or
installer file.

EXPERIMENTAL 2026-11-11: artist keys ignore leading/trailing
whitespace (not stable, not installed anywhere, on top of the
2026-11-10 experimental staging). Rips and taggers leave stray
spaces in artist metadata, and the 2026-11-03 case fix did not cover
them: "Drake" and "Drake " counted as different artists, so they
could land back-to-back in a shuffle or Flow and count separately
toward Rediscover's max-per-artist. The featuring truncation only
stripped the tail, so " Drake feat. X" kept its leading space, and a
whitespace-only artist ("   ") counted as a real artist instead of
never clashing like "" and None. artist_key now strips the raw
string up front and maps whitespace-only to "". Mac spot check if
he wants it: none needed, this is pure Python tested here, no Mac
run proves anything extra. Nothing else in this build changes: only
artists.py and one new test file were touched, no bridge, run.sh,
daily.sh, cli.py, or installer file.

EXPERIMENTAL 2026-11-10: in-memory dedupe validation accepts a
same-song order when given the kept set (not stable, not installed
anywhere, on top of the 2026-11-09 experimental staging). The safety
gate has two forms of the same dedupe rule, and they disagreed: the
file form recomputes the kept set from the dump, but the in-memory
form only saw IDs, so it demanded every unique ID exactly once and
refused a correct dedupe order whenever two IDs were the same song
stored twice. validate_order_text now takes an optional
dedupe_kept_ids (the kept set split_duplicates computes); with it,
the check matches the file form, and without it the old ID-level
rule stays and is documented. Mac spot check if he wants it: none
needed, this is pure Python tested here, no Mac run proves anything
extra. Nothing else in this build changes: only validate.py and one
new test file were touched, no bridge, run.sh, daily.sh, cli.py, or
installer file.

EXPERIMENTAL 2026-11-09: audit counts genre strings
case-insensitively (not stable, not installed anywhere, on top of
the 2026-11-08 experimental staging). The audit's top-genres list
exists so the next genre-map edit is driven by real data, but it
counted raw genre strings, so "Rock", "rock", and "ROCK" were three
genres: genre_distinct was inflated and one genre split across
three lines. Flow itself matches genres case-insensitively, so the
audit's counting contradicted how genres are actually used. Genre
strings are now grouped by their lowercased form, and the displayed
label keeps the first-seen casing so the list still reads as the
library wrote it. Mac spot check if he wants it: `./run.sh audit`
prints the report and changes nothing. Still unproven on a Mac
until he runs it on a real library dump. Nothing else in this build
changes: only audit.py and one new test file were touched, no
bridge, run.sh, daily.sh, cli.py, or installer file.

EXPERIMENTAL 2026-11-08: audit's Flow energy range now uses the real
clock (not stable, not installed anywhere, on top of the 2026-11-07
experimental staging). The audit's "Flow energies (eligible)" line
used to score every track clock-free, while Flow itself scores with
the real clock, so for a library with recently played or recently
added songs the audit's range was wrong by up to 5 points against
what flowPreview actually builds (a song played 5 days ago scores
56 in Flow but 53 in a clock-free audit). audit_library now takes
an optional reference time and the CLI passes the real clock, so
the audit's range is the range Flow builds; without a reference
time the old deterministic behaviour is unchanged, and the BPM
path never uses the clock either way. Mac spot check if he wants
it: `./run.sh audit` prints the report and changes nothing. Still
unproven on a Mac until he runs it on a real library dump. Nothing
else in this build changes: only audit.py, cli.py, and one new test
file were touched, no bridge, run.sh, daily.sh, or installer file.

EXPERIMENTAL 2026-11-07: rediscover-preview prints a full-list pick
summary (not stable, not installed anywhere, on top of the
2026-11-06 experimental staging). rediscover-preview used to print
only the first 25 picks, so the first page hid what the full list is
actually made of. It now prints one extra line after the preview list
covering the whole pick list: "Rediscover picks: N songs, X never
played, Y favorited, Z rated 4-5 stars, forgotten A..B days, max C
per artist." The forgotten range is left out when no pick has a usable
date. The plain rediscover command is unchanged, and the summary
describes picks already computed, so it changes no playlist. Mac spot
check if he wants it: `./run.sh rediscover-preview` prints picks and
the summary line and writes nothing. Still unproven on a Mac until he
runs it on a real library dump. Nothing else in this build changes:
only rediscover.py, cli.py, and one new test file were touched, no
bridge, run.sh, daily.sh, or installer file.

EXPERIMENTAL 2026-11-06: shuffle repair stops wasting tries on
same-artist swaps (not stable, not installed anywhere, on top of
the 2026-11-05 experimental staging). The spacing repair pass
tried up to 30 random swap partners per clash, but swapping two
songs by the same artist can never change the clash count, so
those tries were always wasted, worst when one artist dominates
the list. Same-artist partners are now skipped without burning a
try, and draws per clash are capped at 300 so the loop cannot
spin. Mac spot check if he wants it: `python3 -m unittest
discover -s tests -q` inside the unzipped experimental tree
prints only and changes nothing; there is no preview-only shuffle
command, so do not run a shuffle on a real playlist to test this.
Still unproven on a Mac until a real library shuffle runs
through it. Nothing else in this build changes: only shuffle.py
and one new test file were touched, no bridge, run.sh, daily.sh,
or installer file.

EXPERIMENTAL 2026-11-05: Flow stops jumping ahead of its own arc
(not stable, not installed anywhere, on top of the 2026-11-04
experimental staging). The walk's distance term is symmetric, so on
a near-tie it could pick a song hotter than the target on the rise
or colder than the target on the fall, zigzagging around the arc
instead of tracking it; one pinned case ended a playlist on its
hottest song against a falling tail. Each step now adds a small +5
when a candidate sits on the wrong side of the target for the arc's
direction at that slot: above it while rising, below it while
falling. The +5 only breaks near-ties, a candidate 6+ closer still
wins, artist spacing still wins over everything, and a flat pool is
unaffected. Mac spot check if he wants it: `./run.sh flowPreview`
prints the order and the arc summary line and writes nothing.
Still unproven on a Mac until he runs it on a real library dump.
Nothing else in this build changes: only flow.py, one new test
file, and one updated test expectation were touched, no bridge,
run.sh, daily.sh, or installer file.

EXPERIMENTAL 2026-11-04: Rediscover relaxes its variety rules one
at a time (not stable, not installed anywhere, on top of the
2026-11-03 experimental staging). When a Rediscover pool was too
small to fill under both the per-artist cap and the cooldown, the
picker dropped both rules at once, so it could repeat a recently
picked song even when an extra song by an already-picked artist
would have filled the slot. Now it relaxes one rule at a time:
both rules, then cooldown only, then artist cap only, then
neither, then the usual front-of-list fill. A pool that fills
under both rules behaves exactly as before. Mac spot check if he
wants it: `./run.sh rediscover-preview` prints picks and writes
nothing; on a normal-size library it will likely never reach the
new passes, so that check is safe, not proof. Still unproven on
a Mac until a small pool actually hits the staged passes. Nothing
else in this build changes: only rediscover.py and one new test
file were touched, no bridge, run.sh, daily.sh, or installer file.

EXPERIMENTAL 2026-11-03: artist keys are case-insensitive
(not stable, not installed anywhere, on top of the 2026-11-02
experimental staging). The artists module always documented
case-insensitive matching, but the Python port compared keys with
==, so the same artist spelled differently across rips ("Drake"
vs "drake") counted as two artists and defeated spacing in shuffle
and Flow and the max-per-artist count in Rediscover. artist_key
now returns a lowercased key; keys are only compared, never
displayed, so no output text changes. Mac spot check if he wants
it: `./run.sh rediscover-preview` prints picks and writes nothing.
Still unproven on a Mac until he runs it on a real library dump.
Nothing else in this build changes: only artists.py, test_core.py
expectations, and one new test file were touched, no bridge, run.sh,
daily.sh, or installer file.

EXPERIMENTAL 2026-11-02: flowPreview prints a full-list arc summary
(not stable, not installed anywhere, on top of the 2026-11-01
experimental staging). flowPreview used to print only the first 25
songs, so a flat first page hid whether the full Flow order actually
rises and falls. It now prints one extra line after the preview list
covering the whole order: "Flow arc: N songs, energies lo..hi, starts
X, peaks Y at #P, ends Z." The plain flow command is unchanged, and
the summary describes an order already computed, so it changes no
playlist. Mac test if he wants it: `./run.sh flowPreview` and read
the last line. Still unproven on a Mac until he runs it on a real
library dump. Nothing else in this build changes: only flow.py,
cli.py, and one new test file were touched, no bridge, run.sh,
daily.sh, or installer file.

EXPERIMENTAL 2026-11-01: audit counts same-song library copies
(not stable, not installed anywhere, on top of the 2026-10-31
experimental staging). The audit command now reports how many
library tracks are extra copies of the same song (same artist +
title stored as different library tracks, same rule dedupe uses),
as two numbers: extra copies and how many songs have them. That
explains a dedupe total that lands below the library size instead
of looking like songs went missing. Mac test if he wants it:
`./run.sh audit` on his library dump prints one new line,
"Same-song duplicates: N extra copies across M songs". Audit
changes nothing, so it is safe to try without touching any
playlist. Nothing else in this build changes: only audit.py and
one new test file were touched, no bridge, run.sh, daily.sh, or
installer file.

EXPERIMENTAL 2026-10-31: daily dedupe fallback for all three
targets (not stable, not installed anywhere, on top of v3.0.9
plus the 2026-10-30 Flow relative arc). On 2026-10-31 the
v3.0.9 daily run cleaned the main playlist, then exited at
the SeTeR Rediscover probe's duplicate refusal before shuffle,
flow, or rediscover ran, because only the main playlist had
a fallback. Now a duplicate-only probe refusal for the main
playlist, SeTeR Rediscover, or SeTeR Flow triggers one
in-place dedupe for that target (snapshot before, verified
after, 0 rebuilds, no mapping recorded) plus one re-probe of
the clean target for a fresh mapping, and the daily run then
continues. Any other probe failure, a failed dedupe, or a
re-probe that still refuses stops the run with no second
dedupe attempt. Mac test if he wants it: dedupe "SeTeR
Rediscover" by hand, then re-run daily.sh, is no longer the
only way past a doubled generated playlist; the next daily
run should clean it and finish on its own. Still unproven on
a Mac until a real daily run hits a doubled Rediscover or
Flow playlist and completes.

EXPERIMENTAL 2026-10-30: Flow relative arc (not stable, not
installed anywhere, on top of v3.0.9). This is the 2026-10-29
held build, ported unchanged onto v3.0.9; it is not in stable
v3.0.9. On Spencer's 2026-10-29 audit his library had BPM
missing on 100% of tracks and fallback energies spanning only
47..68, so the fixed 45..90..40 arc aimed at a peak the pool
cannot reach. When every Flow pool track is BPM-missing and
the pool energy range is at least 10, the arc is now rescaled
into the pool's own [min, max] range: start near the pool
floor, peak at the pool max, end at the pool floor. A pool
with any BPM track keeps the fixed arc exactly, and a narrow
fallback range keeps it too. Mac test if he wants it:
`./run.sh flowPreview` on a BPM-less library should show a
rise and fall inside the pool's own energy range, not a climb
toward 90 that never arrives. Preview changes nothing, so it
is safe to try without touching any playlist. Nothing else in
this build changes: no bridge, run.sh, daily.sh, or installer
file was touched for this change.

NEW IN v3.0.2: the 8am daily run AUTO SELF-PROBES. Before it
builds anything, it runs `./run.sh selfprobe` on the daily
playlist and on "SeTeR Rediscover", measuring each mapping on
the target itself under its own sort (Music remembers each
playlist's own sort, so no throwaway sort needs matching and
no mapping can transfer between targets). The 48-hour manual
probe chore is gone; the mapping gate stays: a failed
self-probe fails the whole daily run closed before any build,
and an "other" mapping still aborts. A self-probe on a
playlist with duplicate entries refuses and changes nothing,
so a doubled playlist cannot be auto-probed; since v3.0.4
it is cleaned by trial-dedupe instead (see NEW IN v3.0.4
below), which verifies its own mapping without probing.
You can also self-probe by hand any time:
`./run.sh selfprobe "My New Sandwich Recipe"`.

NEW IN v3.0.3: menu and direct builds AUTO SELF-PROBE too.
v3.0.2 only auto-probed the daily run, so the menu still
refused on a missing mapping. Now every build path (menu,
direct shuffle, rediscover, dedupe, flow, undo, restore)
self-probes the target itself first when no fresh mapping
is recorded, and reuses a fresh mapping with no re-probe.
A failed probe aborts before any dump or apply, with the
probe error named. A doubled playlist still fails closed
at the probe (duplicate refusal unchanged) until deduped.

NEW IN v3.0.4: trial-dedupe breaks that deadlock. Dedupe
no longer probes first: a clean playlist applies nothing
and needs no mapping, a fresh mapping is used directly,
and otherwise dedupe tries its known deduped order
(first occurrence of each song) under mapping forward,
verifies the list read against it, and on failure
restores from the per-run snapshot and tries reversed.
The first mapping that verifies wins and is recorded, so
the next build reuses it; if neither verifies, the
playlist is restored to its pre-dedupe order and no
mapping is recorded. The probe itself is untouched by
this: sortprobe/selfprobe on a doubled playlist still
refuse, because the probe's oracle is a rotation
classification, while dedupe's oracle is verify-after on
the actual desired order. The daily run attempts
trial-dedupe only when the daily playlist's probe refused
on duplicate entries specifically.

NEW IN v3.0.5: restores try BOTH mappings before declaring
CRITICAL. On 2026-10-29 18:59 PT trial-dedupe tried forward
first on the real main playlist (1612 entries, 806 unique);
its true mapping is reversed, so the forward build
verified-failed, as it should, and then the restore inside
that same apply rebuilt the snapshot with the SAME forward
mapping, so it verified-failed too, and the undo restore
failed the same way. No songs were lost: the pre-undo file
proved all 1612 entries were present, in the exact reverse
of the snapshot, and a read-only diagnostic afterwards
proved the current list-read order is exactly the
pre-dedupe snapshot order, so the playlist needs no
restore. The trap was that a restore under a wrong mapping
cannot verify, by the same mechanism as the build failure.
Now every restore (apply-order, undo's pre-undo restore,
and restore-original's snapshot put-back) tries the given
mapping first, then the opposite, each verified against
the snapshot it is returning to, and only declares
CRITICAL if neither verifies. This is NOT a build flip:
a failed build still exits non-zero and records nothing;
a restore retries only to return to a known snapshot.
A trial-dedupe attempt whose restore fails under both
mappings stops critical with the snapshot named and does
not try the other trial mapping on top of a possibly
partial state.

NEW IN v3.0.6: same-song dedupe, plus setup fixes. Dedupe now
removes a song stored as a different library track, not just an
exact-ID repeat: same artist + title after case/accent/space
normalisation, and within 3 seconds of length when both lengths
are known (the dump now carries duration). Titles are never
trimmed, so a live or remastered version is a different song,
and a track with no artist or no title is matched by ID only.
The first copy in the playlist stays. To go back to exact-ID
matching only: `SETER_DEDUPE_MATCH=id ./run.sh dedupe
"Playlist"`. The Rediscover picker also gives one slot to a
song that exists twice in the library. Tradeoff, stated
plainly: same artist + title within 3 seconds merges, first
copy stays, and a dump with unknown durations merges on
names alone. Setup fixes: warn() actually prints its
message, re-running setup from the installed copy no longer
hits a same-file copy error, uninstall refuses a directory
that is not a SeTeR install, and the installer note now
states the daily self-probe behaviour instead of the stale
manual sortprobe instruction.

NEW IN v3.0.7: no more redundant undo restore. When an apply
fails but apply-order's own error says it already restored the
playlist from its per-run snapshot, run.sh now skips the undo
restore and returns to the caller, so a trial-dedupe moves
straight to the other mapping instead of rebuilding the same
snapshot 3 more times and then stopping on undo's "restored to
pre-undo state" exit. A CRITICAL apply, where the internal
restore failed under both mappings, still runs undo as before.
This fixes the 2026-10-29 21:01 trial-dedupe, which rebuilt
the playlist 5 times and stopped at 1612 without ever trying
reversed, even though both restores had succeeded.

NEW IN v3.0.9: dedupe in place, plus a fuller daily run. Daily now refreshes three playlists in order: dedupe + shuffle the main playlist, refresh SeTeR Flow, then refresh SeTeR Rediscover, each with its own self-probe and mapping check first, and a failure stops the run before the next refresh. Shuffle, Flow, and Rediscover each stamp their description "Last reshuffled: <Mac local date/time at the verified apply>", so the daily run leaves that morning's time on all three, not a stale manual-run time; dedupe does not stamp.

NEW IN v3.0.9: dedupe in place. Spencer set a 1-2 rebuild cap for dedupe on 2026-10-30, and a rebuild is the wrong tool for it: dedupe now deletes only the duplicate entries, in descending position order, and leaves every other song exactly where it was. That is 0 rebuilds on success, no mapping, no probe, no trial, and no mapping recorded; a rebuild happens only if a failed run needs its snapshot restore. Presence dedupe (v3.0.8) was built but never published and is superseded by this; its presence verify code remains in apply-order, unused by dedupe.

NEW IN v3.0.8 (built, never published, superseded by v3.0.9): dedupe verifies presence only. Per Spencer
2026-10-30, dedupe need not keep the original order, so a
dedupe apply now checks the landed song set, same count and
every desired song present, in any order. That makes dedupe
need no mapping, no probe, and no trial: one build lands
the unique songs and passes, under either mapping. A
presence success proves nothing about the sort, so dedupe
records no mapping; the next shuffle or flow self-probes
the now-clean playlist for its true mapping. Shuffle,
flow, and every restore still verify exact order.

## Stable preparation (v3.0.9)

Stable name: v3.0.9. Daily time: 8:00 AM, matching v2.6. The
installer records `3.0.9`. No tag or release is created by
this tree itself; publishing is a separate, explicit step.

```bash
bash setup-python.sh                     # install + 8:00 AM daily run
bash setup-python.sh --no-daily          # install only, no schedule
bash setup-python.sh --hour 9            # install + daily run at 9:00 AM
bash setup-python.sh --uninstall         # remove Python schedule + install dir
bash migrate-to-python.sh --dry-run      # print the migration plan, change nothing
bash migrate-to-python.sh --confirm      # disable v2.6 daily job, enable Python job
bash migrate-to-python.sh --rollback     # restore the v2.6 daily job
```

Installer facts: local files only, nothing downloaded; new install
dir `~/Documents/SeTeRShufflePython`; new plist label
`com.seter.python.daily`; the daily hour lives in exactly one place
(`DAILY_HOUR`/`DAILY_MINUTE` at the top of `setup-python.sh`).
Daily facts: `daily.sh` writes a daily library manifest (kept 14
days), auto self-probes both targets, then dedupes, shuffles,
and refreshes "SeTeR Rediscover"; it still REFUSES without a
fresh (<48h) per-target mapping for each target after the
self-probes, and a failed self-probe fails the run closed
before any build. The former stable-prep gaps are closed in
the drop-in package: `./run.sh menu` (Terminal menu; it
pre-checks the target's mapping and refuses before any dump
when none is recorded, and a blank size no longer crashes on
macOS bash 3.2), a
"Last reshuffled" playlist description stamp after verified
shuffle/flow applies (best-effort, never fails the apply),
macOS notifications on success and failure, `./run.sh shuffle
[size]` (100/250/500/1000/all, whole-library only), and dedupe
lines naming every removed duplicate. Flow energy flatness for
gospel-heavy libraries was fixed on the synthetic profile in
the 2026-10-29 flow-fix entry (arc-first walk, finer vibe
score); it is not claimed fixed against Spencer's real library
until the Step 10d flowPreview run on a Mac shows a rising
arc.
Migration facts: v2.6 script, backups, apps, and history are never
deleted or edited; only the v2.6 plist is renamed to
`.disabled-<timestamp>` on `--confirm`, and `--rollback`
restores it. Rediscover history carries over as-is because the
Python run reads the same file.

## Architecture: what each part does

```
Music app
  │  dump-library.applescript  (read-only: library/playlist -> JSON)
  ▼
Python core (seter_shuffle/)   (decides an ordering, nothing else)
  │  --order-txt: one persistent ID per line
  ▼
apply-order.applescript        (snapshot -> build -> verify -> restore)
```

- **Python core** (`seter_shuffle/`, standard library only, no pip
  dependencies): Fisher-Yates shuffle with v2.6 artist spacing,
  Rediscover scoring/picking from v2.6, and Flow ordering from the
  experimental AppleScript build. It works only on a JSON dump. It
  never opens Music, never edits the dump, and never writes a playlist.
  This is the part that is fully testable on any machine.
- **Bridge** (`bridge/`, AppleScript files): the only code
  that talks to Music. `dump-library.applescript` dumps a library or
  playlist to JSON. `sort-probe.applescript` measures the
  end-to-end build-to-list mapping on a throwaway the user sets to
  the target playlist's sort (Playlist Order descending for the
  2026-10-28 failure), reporting forward, reversed, or other
  (which aborts everything); run.sh records that mapping
  PER-TARGET, with the throwaway name and a user-declared sort
  label, and requires a fresh one (48 hours) before every apply
  and undo. A mapping measured on one playlist's sort NEVER
  transfers to a playlist with a different sort: the 2026-10-29
  15:38 PT Flow runs proved it, using the main playlist's
  reversed (descending) mapping for the new, default-sorted
  SeTeR Flow playlist and failing verification, correctly.
  Flow needs its own sortprobe on a throwaway set to SeTeR
  Flow's sort (see BRIDGE-SAFETY.md modes 35 and 36).
  The old `probe-order.applescript` (fresh 3-song probe) is a
  standalone sanity check only and is consulted by no build: a
  fresh playlist does not share a real playlist's sort, and the
  track `index` channel it used is not a manual-order reference
  (2026-10-29 diagnostic; see BRIDGE-SAFETY.md mode 30).
  `apply-order.applescript` snapshots a playlist's IDs to a backup
  file BEFORE changing anything, rebuilds it under the recorded
  mapping, verifies exactly against the desired list-read order,
  and restores from the backup on any failure; it refuses the
  Library itself, smart playlists, and anything that is not a
  regular user playlist, refuses ambiguous playlist names instead
  of guessing, and fails if the library shrank during the run.
  Every rebuild first proves its delete took effect: it deletes,
  re-reads, and confirms 0 song entries, retrying up to 5 times
  with a 5-second settle delay, and duplicates nothing if entries
  remain (2026-10-29 doubling failure: a real playlist doubled to
  1612 entries, consistent with a lagging delete; the guard does
  not depend on that mechanism being proven). `undo.applescript`
  replays a backup file with the same strictness, and snapshots
  the current playlist first so a failed undo is recoverable.
  `restore-original.applescript` is a one-off recovery script that
  also takes a recorded mapping (no probe, no flip), runnable
  through `./run.sh restore` with the same freshness-checked
  mapping gate as undo. Backups are per-run: the apply writes to
  a fresh per-run snapshot file, installed as the main backup only
  after a verified successful apply, so a failed run can never
  overwrite the only good backup (the 00:41 run did exactly that
  under the old scheme). The bridge never decides an order, and
  never flips on failure: a failed verify restores and exits
  non-zero. Full failure-mode table, the one case AppleScript
  cannot cover (power loss / force-quit mid-write), and the Mac
  verification procedure: see `BRIDGE-SAFETY.md`. The bridge has
  been reviewed line by line but never executed: this machine has
  no Music app or osascript, so until the Mac procedure in
  `BRIDGE-SAFETY.md` has been run, treat it as reviewed, not
  tested.
- **Validation** (`seter_shuffle/validate.py`, plus `validate-order`
  and `validate-backup` CLI commands): the same refuse rules as the
  bridge, applied in Python before osascript ever runs, so a bad
  order is caught while the playlist is still untouched. Empty
  orders, IDs missing from the dump, shuffle orders that are not
  exactly the dump's songs (same songs, same multiplicities),
  orders repeating an ID more times than the dump does, truncated
  orders (the text file must agree exactly with the order JSON),
  and malformed files are all refused. Backups are validated too,
  with one deliberate difference: duplicates are allowed in a
  backup (a real playlist can hold the same song twice) and an empty
  backup is valid (it snapshots an empty playlist).
- **Runner** (`run.sh`): wires bridge -> core -> bridge, logs to
  `~/Library/Logs/seter-shuffle-python/run.log`, and keeps backups
  under the same directory. `check-python.sh` verifies a real python3
  before Music is touched (see below).

The interchange between core and bridge is deliberately split in two:
JSON for humans and the Python core, and a plain one-ID-per-line text
file for the bridge, because AppleScript has no JSON parser and
parsing JSON by hand in AppleScript would be a new bug factory.

## Commands on a Mac

From this directory:

```bash
./run.sh audit                  # tag-coverage audit, change nothing (run this first)
./run.sh flowPreview            # print the would-be Flow order, change nothing
./run.sh flow                   # build or refresh "SeTeR Flow"
./run.sh shuffle                # shuffle the whole library into "SeTeR Shuffle"
./run.sh shuffle "My Playlist"  # shuffle one playlist in place
./run.sh rediscover-preview     # print Rediscover picks, change nothing
./run.sh rediscover             # refresh "SeTeR Rediscover" (history is
                                # recorded only after a successful apply)
./run.sh undo "SeTeR Flow"      # restore a playlist from its last backup
./run.sh dedupe "My Playlist"   # remove duplicate entries (unique songs,
                                # first-occurrence order); applies nothing
                                # if the playlist has no duplicates.
                                # NOTE: dedupe preserves the current
                                # list-read order, not a backup order,
                                # so on a reversed doubled playlist
                                # it yields unique songs in reversed
                                # order; a backup-order restore is a
                                # separate step afterwards.
./run.sh restore "My Playlist" backup.txt
                                # restore a playlist from a given backup
                                # file (freshness-checked mapping, same
                                # gate as undo)
```

Direct core commands (no Music involved, useful for testing):

```bash
python3 -m seter_shuffle.cli audit --library dump.json
python3 -m seter_shuffle.cli flowPreview --library dump.json --seed 42
python3 -m seter_shuffle.cli flow --library dump.json --out order.json --order-txt order.txt
python3 -m seter_shuffle.cli shuffle --library dump.json --out order.json --order-txt order.txt
python3 -m seter_shuffle.cli dedupe --library dump.json --out order.json --order-txt order.txt
python3 -m seter_shuffle.cli rediscover-preview --library dump.json --history rediscover-history.tsv
python3 -m seter_shuffle.cli record-history --history rediscover-history.tsv --ids-file order.txt
python3 -m seter_shuffle.cli validate-order --library dump.json --order-txt order.txt --order-json order.json --mode shuffle
python3 -m seter_shuffle.cli validate-order --library dump.json --order-txt order.txt --order-json order.json --mode dedupe
python3 -m seter_shuffle.cli validate-backup --backup backup.txt
```

`flowPreview` and `rediscover-preview` never call the apply script and
never write history. `rediscover` (the core command) also does not
write history; the runner records it only after the apply succeeds, so
a failed apply never burns a song's cooldown. `audit` never touches
Music at all: it only counts what is in a dump file.

## BPM is not attached to every song, and Flow now handles that

No, not every song in Apple Music has a BPM. Music does not analyse
tempo for you: the BPM field comes from the track's own metadata, and
it is often blank, especially for rips, older files, and tracks whose
source never wrote a tempo tag. A library with most BPM missing is
normal metadata, not proof the dump failed.

That is exactly what Spencer's 2026-10-28 preview showed: 940 songs
dumped, 938 eligible, but almost every energy at exactly 50, because
missing BPM defaulted to 50 and his gospel/Christian genres matched
no genre group. Two causes look identical in a preview, and `audit`
separates them: if BPM is present for *some* songs, the dump works
(a dump bug would lose BPM for the whole list at once) and the rest
truly lack BPM metadata. If BPM is present for *zero* songs, suspect
the dump script first.

The missing-BPM fallback model (songs WITH BPM score exactly as
before) is a vibe score, not a tempo: base 50, an expanded genre
map (gospel/christian/worship -2, latin/reggaeton +6,
afrobeats/reggae +4, soundtrack -3, old groups unchanged), plus
group-8 genre subgroups (choir/choral -4, worship/praise -2,
contemporary +3), finer tiered plays (0/1/2/3/4/6/8/10/12 across
0/1/2-3/4-7/8-14/15-24/25-39/40-69/70+ plays), rating (3 stars +2,
4-5 stars +5, 1-2 stars -10), favorited +5, finer skip bands
(>90% skips -8, >50% -5, 25-50% -2, never-skipped well-played
+2), a release-year era band (2020+ +2, 2010s +1, 2000s 0,
1990s -1, older -2), and played-date recency plus date-added
newness when a clock is supplied. Skip-heavy songs stay eligible;
they just do not score like never-skipped ones. The fallback
spread is deliberately narrower than the BPM range: without a
tempo, these are weak signals, and a wide spread would be
guessing a tempo, not measuring one. The walk is arc-first:
genre cost 0/3/8 and year cost 0/2/4, plus +4 for repeating the
exact previous energy, so the arc target drives the walk and
genre continuity only breaks near-ties (the old 0/8/20 genre
cost outweighed the whole energy distance and flattened the
first half into one cluster). On a gospel-heavy synthetic
profile mirroring Spencer's library, the old walk gave a
16-long run of exactly 50 then a cliff to 72-77; the fixed
walk rises gradually and falls, with 16 distinct energies in
the first 25. That synthetic result is not proof against his
real library: the Mac flowPreview step in
STABLE-PROMOTION-TESTS.md must show a rising arc before this
is claimed fixed.

Tie-breaking also changed: on an exact cost tie the walk now prefers
a genre group different from the previous pick, then higher
familiarity (plays, favorited, rating), then the earliest pool song,
so flat-energy pools stop coming out in raw library order. The order
stays deterministic.

## The python3 check

macOS ships a python3 stub that just prompts to install developer
tools. `check-python.sh` requires a real interpreter (3.9+) and fails
loudly otherwise, instead of letting a scheduled run break silently:

```bash
./check-python.sh
# -> /usr/bin/python3 (Python 3.12.3)   on success
```

If it fails, install real Python (Xcode Command Line Tools with
`xcode-select --install`, python.org, or Homebrew) or point
`SETER_PYTHON` at a real interpreter, for example:

```bash
SETER_PYTHON=/opt/homebrew/bin/python3 ./run.sh flowPreview
```

## Settings

Defaults match v2.6 plus the experimental Flow settings. Override them
on the core command line, for example `--flow-size 30`,
`--artist-spacing 1`, `--rediscover-min 30`, `--max-per-artist 2`,
`--cooldown-days 14`, `--stale-days 60`. The runner uses defaults;
edit `run.sh` if you want different ones baked in.

## What was actually tested, and what was not

Tested here, for real (518 tests, all passing):

```bash
python3 -m unittest discover -s tests -v
```

Shuffle set preservation and replayable seeds, artist spacing
(including the featuring rule and the best-effort limit), Flow energy
(missing BPM/genre defaults, bands, nudges, clamps), the wave arc,
Flow with 0/1/2 songs, Flow eligibility (disliked/unchecked out,
skip-heavy kept, unlike Rediscover), Flow artist spacing winning over
vibe, Rediscover eligibility/weights/target clamps, max-per-artist and
cooldown enforcement, history load/record roundtrips, duplicate-ID
rejection, CLI previews proving they leave the input file
byte-identical and write nothing to any library, plus the new work:
audit counts matching a known fixture (including BPM zero vs
missing), the missing-BPM spread, gospel/Christian/latin/afrobeats/
soundtrack genre mapping, BPM-present songs scoring exactly as
before, the skip penalty applying only without BPM, and the
movement/familiarity tie-break being deterministic, plus the new
work: dedupe first-occurrence order (including the reversed-doubled
shape), dedupe validation refusing repeats, drops, and invented
IDs, the CLI dedupe command on dump files, and structural guards
for the delete-empty handler in all four bridge scripts, the
per-run backup chain, the sort-probe mapping deletion on
failure, and the restore command, plus the .3 mapping-gate
error visibility, plus the .5 per-target mapping guard and
the undo/restore -1728 empty fallback (518 tests total):
failures in `mapping_for_build` and
`probe_mode` (both called inside `$(...)`) now go to the log
file AND stderr via `logerr()`, never to stdout, so a refused
build shows its `GATE FAILED` line on the terminal instead of
stopping silently after "compute shuffle order" (the .2
behavior) or polluting the captured mapping (the .1 bug).
The Mac checklist that gates any stable promotion is
`STABLE-PROMOTION-TESTS.md`: sortprobe, sort controls,
title-sorted abort with a visible refusal, dedupe, failure
safety, negatives, flow, rediscover-preview, and restore, all
on throwaways first, real playlist only with explicit approval.

NOT tested, and not claimed to work until a Mac run proves it (the
full list is in CHANGELOG-EXPERIMENTAL-PYTHON.md). This warning is
stronger than it was for .4, because .4 was also "reviewed, not
tested" and then failed on a real 806-song playlist (its pre-undo
snapshot came back the exact reverse of the original backup; see
BRIDGE-SAFETY.md mode 29):

- All bridge scripts: every Music interaction, including bulk
  property reads for bpm/year/dates, `month as integer` and the
  date-component ISO formatting in the dump script, `first track ...
  whose persistent ID is ...`, duplicate-to-playlist ordering, the
  verify/restore paths, and now the probe itself (including whether
  the track `index` property is exposed on playlist tracks at all).
- `run.sh` end to end: it needs osascript and Music, neither of which
  exists on the Linux machine this was built on. Its shell syntax was
  checked (`bash -n`), and its python-path parsing was fixed during
  review, but no Mac run has happened.
- The macOS python3 stub behaviour: the check script is written to
  fail loudly, but the stub's exact behaviour on a given Mac has not
  been observed from here.

Suggested Mac verification order: `./check-python.sh` first, then
the BRIDGE-SAFETY.md Stage 0 sequence: the read-only diagnostic on
the target, the UI sort check in Music, then
`./run.sh selfprobe "<target>"` (v3.0.2, preferred: the target
itself, under its own sort), or `./run.sh sortprobe
"<throwaway>" "<target>" "<sort-label>"` on a throwaway set to
the target's sort (Playlist Order descending for the 2026-10-28
failure), which must return a forward or reversed mapping and
restore the probed playlist; an "other" mapping aborts
everything by design. The mapping is recorded for that target
only; a build for any other target refuses until that target
has its own probe. The old `./run.sh probe` (fresh 3-song probe) is a
standalone sanity check only and does not substitute for the
sort-matched probe. Then `./run.sh audit` (changes nothing, and
answers whether BPM is truly missing or the dump is failing), then
`./run.sh flowPreview` (changes nothing), then the full throwaway
procedure in BRIDGE-SAFETY.md (Stage 0 controls, Stage 1 happy
path, Stage 2 negative tests, Stage 3 a real playlist you can
afford to have rewritten, with explicit approval). Nothing in
this procedure runs on a real playlist first, and nothing runs on
"My New Sandwich Recipe" until Stage 3 at the earliest.

## Known differences and quirks, kept on purpose

- Flow's 2-song arc ends at the peak instead of easing down, exactly
  as in the AppleScript experimental build. Fixing it would make the
  two builds disagree; it is flagged, not silently changed.
- Genre grouping is substring matching, so "K-Pop" lands in the pop
  group, exactly as in the AppleScript build.
- Rediscover picks are shuffled and artist-spread after picking, as
  in v2.6; the playlist does not play best-songs-first.
- Artist spacing is best effort. With spacing=2, at least 2 songs must
  sit between repeats, so a library dominated by one or two artists
  cannot be fully separated, and the pass gives up rather than looping.


## What counts as a duplicate (dedupe)

`./run.sh dedupe <playlist>` and the daily dedupe step remove a playlist
entry when it is

- the same Music track as an earlier entry (same persistent ID), or
- the same song stored as a different library track: same artist and
  title after ignoring case, accents-as-written and extra spaces, and,
  when the dump knows both lengths, within 3 seconds of each other.

The first copy in the playlist stays. Titles are never trimmed, so
"Song (Live)" or "Song - Remastered" are different songs, and a live or
radio-edit version with a clearly different length is kept. Tracks with
no artist or no title are matched by ID only. Only playlist entries are
removed; nothing leaves your library, and the usual backup / verify /
restore gates apply.

To go back to exact-ID matching only: `SETER_DEDUPE_MATCH=id ./run.sh dedupe "Playlist"`
(for the daily run, add `SETER_DEDUPE_MATCH=id` to the launchd plist's
`EnvironmentVariables`). The Rediscover picker also gives one slot to a
song that exists twice in the library.
