# Experimental changelog, Python core

This file tracks the Python experimental build only. Stable releases
(v2.6 is current stable) are untouched by anything here, and so is the
AppleScript experimental build. The Python version is published, if at
all, as a prerelease, never as stable, and is never auto-installed on
a Mac. The daily stable run stays AppleScript until Spencer approves
the exact stable change list for the proposed v3.0 promotion; this
entry is preparation for that decision, not the promotion itself.

## 2026-11-20 — EXPERIMENTAL: AI tagger no longer sends BPM 0 (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-20.3 staging
(exp-2026-11-20.3, 553 tests, published as a prerelease the same
day). Spencer ran `ai-selftest` on his Mac and pasted the raw
reply: BPM 72 -> energy 72, BPM 116 -> energy 116, no BPM ->
energy 0. The model copies the BPM number straight into energy,
and his whole library dumps BPM 0, so every song came back energy
0 and got cached that way in ai-tags.json. Moods did vary
(calm/dark), so the model reads the song lines; only energy is
echoed.

What changed, nothing else:
- `build_prompt` in seter_shuffle/ai_tags.py now treats BPM 0
  the same as a missing BPM: an empty BPM field. Real non-zero
  BPM values are still sent. The same rule is used in
  `track_signature`, so prompt and signature agree.
- PROMPT_VERSION bumped 1 -> 2. The cache freshness check
  compares the stored sig against the current one, and the sig
  includes the prompt version, so every v1 tag (including the
  2026-11-20 zero tags) is treated as stale and re-tagged on
  the next AI Flow run. No manual cache deletion is needed;
  deleting ai-tags.json by hand is still a safe fallback.
- No INSTRUCTIONS change: with no BPM number in the prompt
  there is nothing left to echo. No schema, cache-format, or
  tagger redesign.

## 2026-11-20 — EXPERIMENTAL: bare run.sh opens the menu, plus an Options submenu (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-20.2 staging
(exp-2026-11-20.2, 518 tests, published as a prerelease the same
day). Spencer asked for two things: run.sh should go straight to
the menu when run with no arguments, and the menu should have an
Options section for the new features. Both are in this build.

What changed, nothing else:
- Bare `./run.sh` opens the interactive menu when stdin is a
  terminal (same as `./run.sh menu`). With piped or redirected
  stdin it keeps the old behaviour (usage to stderr, exit 2),
  so a bare run in a script or launchd job can never hang
  waiting for input nobody will type. Every named subcommand
  works exactly as before.
- Menu choice 8) Options opens a submenu showing the current
  values and letting him toggle: AI tagging for Flow, split
  collabs, and probe max age (0-40 hours, 0 = probe every day).
  It confirms each change, rejects a bad probe number with a
  clear message, and 0 returns to the main menu without
  quitting it. The submenu reminds him that AI tagging needs
  `sudo fm license` once plus `ai-selftest` before Flow uses it.
- The options persist in three small files under the
  SeTeRShuffle settings dir (the same dir the AI marker and tag
  cache already use): `ai-enabled` (marker, as before),
  `split-collabs-enabled` (marker), and `probe-max-age-hours`
  (one number). The Python CLI already reads the AI marker
  itself and SETER_SPLIT_COLLABS, so run.sh only turns the
  split-collabs marker into that env var at startup, and
  daily.sh only reads the probe-age file. An env var already
  set wins over the file, and the menu says so instead of
  pretending a toggle took effect. A persisted value is honored
  by menu commands, direct commands, and the daily run: menu
  children are fresh run.sh processes that re-read the files,
  and the toggle keeps the in-process env in step with the
  marker so a stale value can never leak into a child.
- tests/test_menu_options.py (35 tests): bare-run TTY gating
  (pty test plus piped-stdin usage test), options read/write
  and probe-number validation, the submenu end to end, the
  env-override notices, and daily.sh honouring the probe-age
  file in the stub-run harness (skip, zero, env-wins, and the
  over-40 clamp).

Version stays 3.0.11 throughout. The Options submenu touches
nothing in Music and authorizes nothing.

## 2026-11-20 — EXPERIMENTAL: v3.0.10 menu playlist picker grafted in (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-20.1 staging
(exp-2026-11-20.1, 503 tests). Spencer approved adding the picker
because the experimental line never had it: publishing without it
would regress the menu from a numbered playlist list back to typed
names. This closes that one known divergence from stable v3.0.10.

What was ported, nothing else: bridge/list-playlists.applescript
as-is from v3.0.10 (read-only, verified: it only reads the name
of every user playlist and prints one per line), the
menu_pick_playlist function plus its header comment, and the
menu call sites for shuffle, dedupe, and undo in run.sh
(numbered list, 0 to type a name, L for whole-library shuffle,
falls back to typing if the listing fails or is empty).
run.sh was NOT copied wholesale: the experimental run.sh keeps
its own single-run lock and everything else, only the picker
was grafted in. The picker changes nothing in Music and
authorizes nothing: every caller still runs its own gates
afterwards (shuffle's and undo's ensure_mapping_for, dedupe's
own no-precheck path). Version stays 3.0.11. Tests: 518 total
(503 + the 15 picker tests from v3.0.10), all passing here.
Mutation-checked: neutering the numbered pick fails the pick
test, removing the call sites fails the wiring test. The
playlist-listing script itself is still unproven end to end on
a real Mac (already true for v3.0.10): if it fails, the menu
falls back to typing a name.

## 2026-11-20 — EXPERIMENTAL: Claude's v3.0.11 candidate merged into the experimental line (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-19
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost + the 2026-11-06 shuffle repair same-artist skip +
the 2026-11-07 rediscover-preview summary + the 2026-11-08
audit clock fix + the 2026-11-09 audit genre-case fix +
the 2026-11-10 in-memory dedupe kept-set fix + the 2026-11-11
artist-key whitespace fix + the 2026-11-12 shuffle spacing
summary + the 2026-11-13 flow arc summary in the real `flow`
command + the 2026-11-14 rediscover pick summary in the real
`rediscover` command + the 2026-11-15 record-history
confirmation + the 2026-11-16 Rediscover weight-ordered fill +
the 2026-11-17 Flow stranded-song rule + the 2026-11-18
Rediscover never-played base + the 2026-11-19 shuffle repair
scan fallback), plus everything in Claude's v3.0.11 candidate
zip (sha256 23fdf5d8c01ebe5eb1bf700092d944383550b24631846c3c9ceb4c673c41fcf4,
reviewed 2026-11-20, 385 tests passing on its own v3.0.10 base).

What the candidate brings in, nothing dropped:
- Time-skew fix: `tracks.dump_now()` measures "now" in the same
  frame as the dump's dates. The bug is real, verified in the
  bridge: dump-library.applescript `jsonDate` writes local
  wall-clock components with a trailing Z, and `parse_date`
  reads it as UTC, so every age was off by the Mac's UTC offset
  (7-8 hours in Seattle). Flow, the audit, and Rediscover's
  forgottenness math now use dump_now().
- Single-run lock in run.sh and daily.sh: one lock directory per
  state folder (mkdir is atomic; macOS has no flock(1)), pid +
  start time recorded, stale takeover when the owner is dead or
  the lock is older than 12 hours, refusal exits 3, trap
  releases on exit, read-only commands (audit, previews, menu)
  and dry runs skip it, child run.sh calls inherit
  SETER_LOCK_HELD=1.
- Probe cadence in daily.sh: SETER_PROBE_MAX_AGE_HOURS=N (1..40,
  default 0 = probe every target every day, as before) skips a
  target's self-probe while its recorded mapping is younger than
  N hours. The 48-hour mapping check still applies.
- Optional AI tagging for Flow (`seter_shuffle/ai_tags.py`, off
  by default): Apple's on-device `fm` CLI tags pool songs with
  energy 0..100 and a mood bucket, cached by persistent ID with
  a metadata signature, blended into Flow at Settings.ai_blend
  with a mood-continuity walk cost. Fail-soft throughout: no
  `fm`, unaccepted license, timeout, or bad JSON leaves songs
  on heuristic energy and Flow runs as before. Turned on with
  --ai, SETER_AI=1, or the ~/Documents/SeTeRShuffle/ai-enabled
  marker file (the marker also covers the daily run). The
  `ai-selftest` subcommand checks the `fm` CLI on the Mac
  before anything is turned on.
- Optional --split-collabs (off by default): "A & B", "A, B",
  "A x B" and similar count as artist "A" for spacing and caps.
- Rediscover history dates now use the local date instead of UTC.

Overlaps, reconciled (one implementation each, no test deleted):
- Artist case-insensitive keys (exp 2026-11-03) and whitespace
  trim (exp 2026-11-11) vs Claude's artist_compare_key: kept
  the experimental line's normalized artist_key and built
  Claude's artist_compare_key on top of it (NFKC + casefold +
  internal-whitespace collapse + split_collabs). All core call
  sites now use artist_compare_key. One assertion in Claude's
  test_v3011_fixes.py was updated to the merged contract:
  artist_key("ABBA") is "abba" in this line (the experimental
  test_core pins the normalized key; Claude's "keeps case" claim
  was true only of v3.0.10's test_core). The test itself stays.
- Rediscover weight-ordered fill (exp 2026-11-16) vs Claude's:
  identical ordering (heaviest first, ties keep library order);
  kept the experimental implementation. Ordering is pinned by
  the experimental test_rediscover_fill_weight.py: reverting
  the fill to library order fails 2 of its 4 tests (verified
  on a copy this run). Claude's own fill test does not pin
  ordering and is kept as a reach-the-target guard only.
- The experimental never-played base 1.0 (2026-11-18) is kept;
  Claude's tree still had the old 0.4 and was not carried over.

Version is 3.0.11 throughout: seter_shuffle/__init__.py,
setup-python.sh VERSION_MARKER, install-or-update.sh and
SeTeR-Shuffle-Install.command banners, so an install stamps
installed-version.txt as 3.0.11. The six installer tests that
pinned "3.0.9" now pin "3.0.11". Historical "v3.0.9"
attributions in comments are untouched. README test counts
fixed (141 / 161 were stale) to the new total, 503.

Note for the publish-time merge: stable has since moved to
v3.0.10, which includes the daily fallback and the menu picker.
This build still does NOT include the v3.0.10 menu picker
(no bridge/list-playlists.applescript, no picker in run.sh, no
test_menu_picker.py): the experimental line forked from v3.0.9
and the picker was never carried over. That gap predates this
merge and is left open deliberately; the stable-promotion merge
must close it, or a later experimental build must. Everything
else in this build is a delta on the experimental line, not on
stable. Tests: 503 passed here (443 baseline + 60 new).

## 2026-11-19 — EXPERIMENTAL: Shuffle repair scans for a fixing swap when random tries miss it (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-18
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost + the 2026-11-06 shuffle repair same-artist skip +
the 2026-11-07 rediscover-preview summary + the 2026-11-08
audit clock fix + the 2026-11-09 audit genre-case fix +
the 2026-11-10 in-memory dedupe kept-set fix + the 2026-11-11
artist-key whitespace fix + the 2026-11-12 shuffle spacing
summary + the 2026-11-13 flow arc summary in the real `flow`
command + the 2026-11-14 rediscover pick summary in the real
`rediscover` command + the 2026-11-15 record-history
confirmation + the 2026-11-16 Rediscover weight-ordered fill +
the 2026-11-17 Flow stranded-song rule + the 2026-11-18
Rediscover never-played base). Note for the publish-time merge:
stable has since moved to v3.0.10, which includes the daily
fallback and the menu picker but not the relative arc, the audit
change, the preview changes, the artist-key changes, the
staged-relaxation fix, the directional-cost fix, the repair fix,
the rediscover-preview summary, the audit clock fix, the
genre-case fix, the kept-set fix, the whitespace fix, the shuffle
summary, the flow summary, the rediscover summary, the
record-history confirmation, the weight-ordered fill, the
stranded-song rule, or the never-played base, so this build is
still a delta on the experimental line, not on stable.

**Why, from a real measured gap, not a guess.** The repair pass
fixes a same-artist clash by swapping the clashing song with a
random partner, keeping the swap only when it strictly reduces
the local clash count. Random draws can miss a reducing partner
that exists: with 30 tries over a big list, a rare good partner
is usually never drawn, so the pass gave up on a clash a single
swap would have fixed. Verified live here before the fix: in a
100-song pool with one artist on 45 songs, spacing 1, the pass
left 1.60 clashes on average over 40 seeds (only 9 runs
clash-free), and in a 846-song pool with one artist on 300 songs,
spacing 2, it left 77.1 on average over 10 seeds.

**What changed.** When the random tries fail on a clash,
`spread_artists` now scans the partners in order and takes the
first swap that strictly reduces the local clash count. The scan
has its own budget (5,000 swap evaluations per call), separate
from the 20,000 random-try budget, so a long scan on one clash
cannot starve the random tries for later clashes: a prototype
sharing the 20,000 budget made the 846-song pool worse (77.1 to
91.0 average clashes), while the separate budget makes it better
(77.1 to 74.8). Same-artist partners are still skipped, the same
local-clash measure decides, and the pass is still best effort:
a list one artist dominates cannot be fully separated, and the
pass still gives up rather than looping. Only
seter_shuffle/shuffle.py changed, plus one new test file and one
updated expectation in tests/test_spread_same_key_skip.py (the
pinned order there is now clash-free, [1, 2, 0, 3] instead of
[2, 1, 0, 3], because the scan also fixes the later clash the
old code left); no bridge, run.sh, daily.sh, cli.py, rediscover,
flow, installer, or other file was touched.
Tests here: full suite 443 passed, 0 failed (438 baseline + 5
new in tests/test_spread_scan_fallback.py: the scan fixes a clash
a stuck random stream cannot, same-artist partners are still
skipped, the dominated-pool improvement, the large-pool
no-starvation check, and the guards; the 3 behaviour tests were
run against the unmodified code first and failed, confirming they
test the new behaviour, while the 2 guards passed on the old code
too, as designed).
Measured live here after the change, same pools and seeds: 45
of 100, spacing 1, 1.60 to 1.12 average clashes left (zero-clash
runs 9 to 15 of 40); 40 of 100, spacing 1, 0.05 to 0.00 (38 to
40 zero); 30 of 100, spacing 2, 2.83 to 2.35; 300 of 846,
spacing 2, 77.1 to 74.8; 380 of 846, spacing 1, 18.9 to 17.0.
UNPROVEN ON A MAC: the scan on a real library; it only changes
which swaps the repair pass tries, the output is still a
permutation of the same songs, and `./run.sh shuffle` on a real
playlist must not be used as the spot check, since that rebuilds
the playlist (the unit tests are the safe check).

## 2026-11-18 — EXPERIMENTAL: Rediscover's never-played songs start at the played-song base (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-17
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost + the 2026-11-06 shuffle repair same-artist skip +
the 2026-11-07 rediscover-preview summary + the 2026-11-08
audit clock fix + the 2026-11-09 audit genre-case fix +
the 2026-11-10 in-memory dedupe kept-set fix + the 2026-11-11
artist-key whitespace fix + the 2026-11-12 shuffle spacing
summary + the 2026-11-13 flow arc summary in the real `flow`
command + the 2026-11-14 rediscover pick summary in the real
`rediscover` command + the 2026-11-15 record-history
confirmation + the 2026-11-16 Rediscover weight-ordered fill +
the 2026-11-17 Flow stranded-song rule). Note for the
publish-time merge: stable has since moved to v3.0.10, which
includes the daily fallback and the menu picker but not the
relative arc, the audit change, the preview changes, the
artist-key changes, the staged-relaxation fix, the
directional-cost fix, the repair fix, the rediscover-preview
summary, the audit clock fix, the genre-case fix, the kept-set
fix, the whitespace fix, the shuffle summary, the flow summary,
the rediscover summary, the record-history confirmation, the
weight-ordered fill, or the stranded-song rule, so this build is
still a delta on the experimental line, not on stable.

**Why, from a real measured skew, not a guess.** A never-played
song added long ago is the most forgotten song possible, but the
old 0.4 base capped it at 2.0 against a 10-play song's 30.0, a
15:1 ratio no amount of forgottenness could close: the forgotten
multiplier caps at 5x for everyone, so the base ratio is the
final ratio. Verified live here before the fix: in an even 50/50
pool (50 never-played, 50 played-10, all added/played 3 years
ago, distinct artists, target 30) never-played songs took 47 of
600 picks (7.8%) over 20 seeds, and a never-played song's weight
was 2.0 against a once-played song's 7.5 at the same
forgottenness.

**What changed.** The never-played base in `rediscover_weight`
is now 1.0, the same base every played song starts from, so the
plays tier (not a 60% unplayed discount) is what separates
played from unplayed. A never-played song tops out at 5.0, still
below a once-played song's 7.5 at the same forgottenness, so
played songs still win at equal forgottenness and unplayed songs
just stop being nearly invisible. The favorited (x3), rating
(x2 / x0.25), and skip (divided by 1 + skips) terms multiply the
new base exactly as they multiplied the old one. No eligibility,
history, artist-cap, staged-relaxation, fill, or ordering rule
changed: the same weights feed the same sampler, and the fill
(2026-11-16) already takes the highest-weight songs left, so it
picks up the new base with no further change. Only
seter_shuffle/rediscover.py changed, plus one new test file and
one updated expectation in tests/test_core.py (the pinned
never-played weight, 0.4 x 5 to 1.0 x 5); no bridge, run.sh,
daily.sh, cli.py, installer, or other file was touched.
Tests here: full suite 438 passed, 0 failed (430 baseline + 8
new in tests/test_rediscover_never_played_weight.py: the weight
value, never-played still below once-played at the same
forgottenness, favorited and rated boosts on the new base, skips
still dividing, recently-added still weight 0, the two even-pool
distributions, and an all-never-played pool still filling the
target; the 6 behaviour tests were run against the unmodified
code first and failed, confirming they test the new behaviour,
while the 2 guards passed on the old code too, as designed).
Measured live here after the change, same pools and seeds: 105
of 600 picks (17.5%, expected 14.3%) against 10-play songs and
251 of 600 (41.8%, expected 40%) against once-played songs.
UNPROVEN ON A MAC: the new base on a real library; it only
changes pick probabilities, and `./run.sh rediscover` on a real
playlist must not be used as the spot check, since that rebuilds
the Rediscover playlist and records history (the unit tests are
the safe check).

## 2026-11-17 — EXPERIMENTAL: Flow's greedy walk stops stranding hot songs at the end (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-16
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost + the 2026-11-06 shuffle repair same-artist skip +
the 2026-11-07 rediscover-preview summary + the 2026-11-08
audit clock fix + the 2026-11-09 audit genre-case fix +
the 2026-11-10 in-memory dedupe kept-set fix + the 2026-11-11
artist-key whitespace fix + the 2026-11-12 shuffle spacing
summary + the 2026-11-13 flow arc summary in the real `flow`
command + the 2026-11-14 rediscover pick summary in the real
`rediscover` command + the 2026-11-15 record-history
confirmation + the 2026-11-16 Rediscover weight-ordered fill).
Note for the publish-time merge: stable has since moved to
v3.0.10, which includes the daily fallback and the menu picker
but not the relative arc, the audit change, the preview
changes, the artist-key changes, the staged-relaxation fix,
the directional-cost fix, the repair fix, the rediscover-preview
summary, the audit clock fix, the genre-case fix, the kept-set
fix, the whitespace fix, the shuffle summary, the flow summary,
the rediscover summary, the record-history confirmation, or
the weight-ordered fill, so this build is still a delta on the
experimental line, not on stable.

**Why, from a real stranded ending, not a guess.** The greedy
walk is short-sighted about the tail: on the fall it can spend
a slot on a cold song that fits a later target perfectly,
leaving a hot song with no target left to land on, so the
playlist ends on that hot song after the cold tail. Verified
live here: a 7-song pool [40, 44, 56, 69, 72, 87, 91] came
back [44, 56, 72, 91, 69, 40, 87], ending on the 87, hotter
than everything except the 91 at the peak. Over 2,000 random
pools the old walk ended 811 of them 20+ hotter than they
started, even though the pools had a cold tail to end on.

**What changed.** At each slot `flow_order` now checks the
unused songs against the later arc targets (rescaled ones
when arc_lo/arc_hi are set): a song is stranded when its best
fit among the later targets is bad (at least 20 off) and
clearly worse than its fit at this slot (at least 10 worse),
and any other candidate costs an extra 500 while a stranded
song exists, so the stranded song is picked now. The 500 sits
between the vibe terms (at most ~21 combined) and artist
spacing (1000): it forces the stranded pick over any vibe
consideration, but spacing still beats it, so a stranded song
by a recently used artist still waits. The rule only fires
when a song genuinely has no good home later: a dense pool
never triggers it, a pool with no cold tail at all is
unchanged (the rule cannot invent one), and with no later
slots the set is empty, so the last slot is untouched. Only
seter_shuffle/flow.py changed, plus one new test file and one
updated expectation in tests/test_flow_relative_arc.py (the
rescaled walk now lands the 80 at the peak slot instead of one
slot late; total arc distance unchanged at 33, peak placement
fixed). No bridge, run.sh, daily.sh, cli.py, installer, or
other file was touched, and no pick, weight, eligibility, or
ordering rule changed except the walk itself.
Tests here: full suite 430 passed, 0 failed (421 baseline + 9
new in tests/test_flow_stranded_songs.py: the pinned 7-song
stranding, a minimal 5-song fall case, a dense pool with lower
arc error and a colder end, spacing still beating stranding,
the rule under the relative arc, a dense relative pool
unchanged, an all-hot pool unchanged, the last slot inert, and
a prepare_flow end-to-end check; the 5 behaviour tests were
run against the unmodified code first and failed, confirming
they test the new behaviour, while the 4 guards passed on the
old code too, as designed). The random-pool probe on the real
implementation: over 2,000 pools the rule improves the total
arc error in 445 pools, worsens it in none, total arc error
139,748 to 129,904, playlists ending 20+ hotter than they
start 811 to 488; a 400-track pool builds a 50-song Flow in
0.07s, so the per-slot scan costs nothing measurable.
UNPROVEN ON A MAC: the walk change on a real library; it
changes only the order Flow picks, and `./run.sh flow` on a
real playlist must not be used as the spot check, since that
rebuilds the Flow playlist (the unit tests are the safe check).

## 2026-11-16 — EXPERIMENTAL: Rediscover's last-resort fill takes the highest-weight songs left (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-15
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost + the 2026-11-06 shuffle repair same-artist skip +
the 2026-11-07 rediscover-preview summary + the 2026-11-08
audit clock fix + the 2026-11-09 audit genre-case fix +
the 2026-11-10 in-memory dedupe kept-set fix + the 2026-11-11
artist-key whitespace fix + the 2026-11-12 shuffle spacing
summary + the 2026-11-13 flow arc summary in the real `flow`
command + the 2026-11-14 rediscover pick summary in the real
`rediscover` command + the 2026-11-15 record-history
confirmation). Note for the publish-time merge: stable has since
moved to v3.0.10, which includes the daily fallback and the menu
picker but not the relative arc, the audit change, the preview
changes, the artist-key changes, the staged-relaxation fix, the
directional-cost fix, the repair fix, the rediscover-preview
summary, the audit clock fix, the genre-case fix, the kept-set
fix, the whitespace fix, the shuffle summary, the flow summary,
the rediscover summary, or the record-history confirmation, so
this build is still a delta on the experimental line, not on
stable.

**Why, from the fill's own job.** The staged sampling passes
(2026-11-04) pick by weight, but when even the neither-rules pass
cannot fill the target, the fill took the front of the candidate
list in library order: the weights that ranked every sampled pick
were ignored for the last slots, so a weak song sitting early in
the dump could take a slot over a stronger song sitting later.
The fill only fires when sampling is starved, which is exactly
when the pool is skewed, so the songs it reaches for are the
ones the weights already ranked lowest. Verified live here with
a rigged draw stream that always lands on candidate 0, so
sampling picks only the first song and the fill supplies the
rest: a 6-song pool with weights 2.0, 180, 7.5, 10, 15, 20 in
library order came back with the 7.5-weight song instead of the
20-weight one.

**What changed.** The fill in `pick_rediscover` now takes the
highest-weight unpicked candidates, ties keeping library order,
so a pool of equal-weight songs fills exactly as before (the
2026-11-04 staged-relaxation pools all weigh the same, and
their tests pass unchanged). The sampling passes, the staged
relaxation order, the weights, the eligibility, and the history
rules are untouched, and the fill still guarantees a full
playlist when sampling alone cannot reach the target. Only
seter_shuffle/rediscover.py changed, plus one new test file and
one docstring line in the staged-relaxation test (its "front-of-
list fill" line now says "weight-ordered fill"); no bridge,
run.sh, daily.sh, cli.py, installer, or other file was touched.
Tests here: full suite 421 passed, 0 failed (417 baseline + 4
new in tests/test_rediscover_fill_weight.py: the rigged-stream
fill takes the strongest remaining songs, a single fill slot
goes to the heaviest song, equal weights keep library order,
and a pool that fills under both rules still respects the cap
and the cooldown across seeds; the two fill-behaviour tests
were run against the unmodified code first and failed,
confirming they test the new behaviour). UNPROVEN ON A MAC: the
fill change on a real library; it only fires when sampling
cannot fill the target, so a normal-size library preview will
likely never reach it, and `./run.sh rediscover` on a real
playlist must not be used as the spot check, since that rebuilds
the Rediscover playlist and records history (the unit tests are
the safe check).

## 2026-11-15 — EXPERIMENTAL: `record-history` prints a confirmation (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-14
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost + the 2026-11-06 shuffle repair same-artist skip +
the 2026-11-07 rediscover-preview summary + the 2026-11-08
audit clock fix + the 2026-11-09 audit genre-case fix +
the 2026-11-10 in-memory dedupe kept-set fix + the 2026-11-11
artist-key whitespace fix + the 2026-11-12 shuffle spacing
summary + the 2026-11-13 flow arc summary in the real `flow`
command + the 2026-11-14 rediscover pick summary in the real
`rediscover` command). Note for the publish-time merge: stable has
since moved to v3.0.10, which includes the daily fallback and the
menu picker but not the relative arc, the audit change, the
preview changes, the artist-key changes, the staged-relaxation
fix, the directional-cost fix, the repair fix, the rediscover-preview
summary, the audit clock fix, the genre-case fix, the kept-set
fix, the whitespace fix, the shuffle summary, the flow summary,
or the rediscover summary, so this build is still a delta on the
experimental line, not on stable.

**Why, from the run log's own job.** Every other step of the daily
run leaves a trace in the run log: shuffle, flow, and rediscover
print a header plus a full-list summary, dedupe prints each removed
duplicate, validate-order and validate-backup print their verdict,
library-manifest prints its count. `record-history` was the
exception: it appended the picked IDs to the cooldown history file
and printed nothing, so the log had no visible proof the cooldown
was actually recorded after a successful Rediscover apply, and an
empty IDs file would have passed through just as silently. Verified
live here: 3 IDs came back with "History recorded: 3 IDs appended
to /tmp/hist-2026-11-15.tsv (cooldown 14 days)." and the file holds
the three dated lines, while an empty IDs file prints "History
recorded: 0 IDs; nothing appended (empty IDs file)." and writes no
file.

**What changed.** `record_rediscover_history` now returns the
number of IDs appended (0 when nothing was written: no picks, or a
cooldown under 1 day), and the `record-history` CLI prints one
confirmation line from that return: "History recorded: N IDs
appended to <history file> (cooldown D days).", singular "1 ID"
when one, "History recorded: 0 IDs; nothing appended (empty IDs
file)." when the IDs file is empty, and "History not recorded:
cooldown is 0 days, nothing was written." when the cooldown is
under 1 day. It is print-only: the history rule, the pruned
entries, and the file content are unchanged, and run.sh already
tees this step's stdout into the run log, so the line lands there
with no runner change. Only cli.py, rediscover.py, and one new
test file were touched; no bridge, run.sh, daily.sh, installer,
or other file was touched. Tests here: full suite 417 passed,
0 failed (410 baseline + 7 new; the new tests were run against
the unmodified code first and all 7 failed, confirming they test
the new behaviour). UNPROVEN ON A MAC: the confirmation is pure
Python and was tested here; no Mac run has exercised it, and the
unit tests are the safe check (the line also lands in the run log
whenever a real Rediscover runs).

## 2026-11-14 — EXPERIMENTAL: the real `rediscover` command prints the pick summary (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-13
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost + the 2026-11-06 shuffle repair same-artist skip +
the 2026-11-07 rediscover-preview summary + the 2026-11-08
audit clock fix + the 2026-11-09 audit genre-case fix +
the 2026-11-10 in-memory dedupe kept-set fix + the 2026-11-11
artist-key whitespace fix + the 2026-11-12 shuffle spacing
summary + the 2026-11-13 flow arc summary in the real `flow`
command). Note for the publish-time merge: stable has since moved
to v3.0.10, which includes the daily fallback and the menu picker
but not the relative arc, the audit change, the preview changes,
the artist-key changes, the staged-relaxation fix, the
directional-cost fix, the repair fix, the rediscover-preview
summary, the audit clock fix, the genre-case fix, the kept-set
fix, the whitespace fix, the shuffle summary, or the flow summary,
so this build is still a delta on the experimental line, not on
stable.

**Why, from the preview's own job.** rediscover-preview has
printed the "Rediscover picks: N songs, X never played, Y
favorited, Z rated 4-5 stars, forgotten A..B days, max C per
artist." line since 2026-11-07, because printing only the first
25 picks hides what the full pick list is actually made of. The
real `rediscover` command printed no such line: run.sh logs the
CLI's stdout, so the daily run log showed only the first 25 picks
of the applied order and hid how much of it was never played,
how much was favorited or highly rated, how long the picks were
forgotten, and whether one artist dominates the list. Verified
live here on the sample fixture: a 4-song Rediscover came back
with 1 never played, 1 favorited, 2 rated 4-5 stars, forgotten
532..2510 days, max 2 per artist, and the old output showed
nothing about that beyond the four listed songs.

**What changed.** One condition in seter_shuffle/cli.py: the pick
summary now prints for `rediscover` as well as
`rediscover-preview`, after the preview list, inside the existing
non-quiet output, and it is the last line printed. It reuses
`rediscover_summary` unchanged, describes picks already computed,
and no pick, weight, eligibility, or ordering rule changed and no
playlist is touched. `--quiet` still prints nothing. The
`rediscover_summary` docstring no longer says "for previews
only", and the CLI help text now mentions the summary. Only
cli.py and rediscover.py (docstring) changed, plus the existing
rediscover summary test file (the old test asserted the real
`rediscover` command printed no summary; it now asserts it prints
the same line rediscover-preview prints, plus a --quiet test). No
bridge, run.sh, daily.sh, installer, or other file was touched.
Tests here: full suite 410 passed, 0 failed (409 baseline + 1
net new test; the new rediscover-prints-summary test was run
against the unmodified code first and failed, confirming it
tests the new behaviour). UNPROVEN ON A MAC: the summary is pure
Python and was tested here; no Mac run has exercised it, and
`./run.sh rediscover` on a real playlist must not be used as the
spot check, since that rebuilds the Rediscover playlist and
records history (the unit tests are the safe check).

## 2026-11-13 — EXPERIMENTAL: the real `flow` command prints the arc summary (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-12
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost + the 2026-11-06 shuffle repair same-artist skip +
the 2026-11-07 rediscover-preview summary + the 2026-11-08
audit clock fix + the 2026-11-09 audit genre-case fix +
the 2026-11-10 in-memory dedupe kept-set fix + the 2026-11-11
artist-key whitespace fix + the 2026-11-12 shuffle spacing
summary). Note for the publish-time merge: stable has since moved
to v3.0.10, which includes the daily fallback and the menu picker
but not the relative arc, the audit change, the preview changes,
the artist-key changes, the staged-relaxation fix, the
directional-cost fix, the repair fix, the rediscover-preview
summary, the audit clock fix, the genre-case fix, the kept-set
fix, the whitespace fix, the shuffle summary, or this fix, so this
build is still a delta on the experimental line, not on stable.

**Why, from the preview's own job.** flowPreview has printed the
"Flow arc: N songs, energies lo..hi, starts A, peaks P at #K,
ends B." line since 2026-11-02, because printing only the first
25 songs hides what the full order actually is. The real `flow`
command printed no such line: run.sh logs the CLI's stdout, so
the daily run log showed only the first 25 songs of the applied
order and hid whether it actually rose and fell. Verified live
here on the sample fixture: a 6-song Flow came back ending at
energy 88 after peaking at 98, the pool could not fall further,
and the old output showed nothing about that beyond the six
listed songs.

**What changed.** One condition in seter_shuffle/cli.py: the arc
summary now prints for `flow` as well as `flowPreview` /
`flow-preview`, after the preview list, inside the existing
non-quiet output, and it is the last line printed. It is
print-only: it reuses `flow_arc_summary` unchanged, describes an
order already computed, and no pick, weight, eligibility, or
ordering rule changed and no playlist is touched. `--quiet`
still prints nothing. Only cli.py changed, plus the existing
flow arc test file (the old test asserted the real `flow`
command printed no summary; it now asserts it prints the same
line flowPreview prints, plus a --quiet test). No bridge, run.sh,
daily.sh, installer, or other file was touched. Tests here: full
suite 409 passed, 0 failed (408 baseline + 1 net new test; the
new flow-prints-summary test was run against the unmodified code
first and failed, confirming it tests the new behaviour).
UNPROVEN ON A MAC: the summary is pure Python and was tested
here; no Mac run has exercised it, and `./run.sh flow` on a real
playlist must not be used as the spot check, since that rebuilds
the Flow playlist (the unit tests are the safe check).

## 2026-11-12 — EXPERIMENTAL: shuffle prints a full-list spacing summary (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-11
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost + the 2026-11-06 shuffle repair same-artist skip +
the 2026-11-07 rediscover-preview summary + the 2026-11-08
audit clock fix + the 2026-11-09 audit genre-case fix +
the 2026-11-10 in-memory dedupe kept-set fix + the 2026-11-11
artist-key whitespace fix). Note for the publish-time merge:
stable has since moved to v3.0.10, which includes the daily
fallback and the menu picker but not the relative arc, the audit
change, the preview change, the artist-key changes, the
staged-relaxation fix, the directional-cost fix, the repair fix,
the rediscover-preview summary, the audit clock fix, the
genre-case fix, the kept-set fix, the whitespace fix, or this
fix, so this build is still a delta on the experimental line,
not on stable.

**Why, from the preview's own job.** flowPreview and
rediscover-preview each print a one-line summary of the whole list
they computed (2026-11-02, 2026-11-07), because printing only the
first 25 songs hides what the full order actually is. shuffle
printed no such line: the first page hid whether the full order
held its artist spacing, and the repair pass is best effort, so
when one artist dominates the list clashes remain with nothing in
the output saying so. Verified live here on the sample fixture:
an 8-song shuffle with one artist on 3 of the songs came back
with 1 same-artist clash still in it after the repair pass, and
the old output showed nothing about that.

**What changed.** New `shuffle_summary` in seter_shuffle/shuffle.py
takes the ordered tracks and the spacing and returns one line:
"Shuffle: N songs, X artists, C same-artist clashes within spacing
S, max M by one artist." The clash count reuses the repair pass's
own `_clashes_at` rule, artist keys come from `artist_key` (so the
case and whitespace fixes apply here too), tracks with no artist
string never clash and do not count toward the per-artist max, and
the max clause is left out when no track names an artist at all.
The CLI prints the line after the preview list for the `shuffle`
command only, inside the existing non-quiet output, and it is
print-only: it is not added to the --out JSON, and it describes an
order already computed, so no pick, weight, eligibility, or
ordering rule changed and no playlist is touched. Only
seter_shuffle/shuffle.py, seter_shuffle/cli.py, and one new test
file were touched; no bridge, run.sh, daily.sh, installer, or
other file was touched. Tests here: 14 new tests in
tests/test_shuffle_summary.py (no clashes when well spread,
back-to-back counts one clash position, spacing-2 clash not
counted at spacing 1, three in a row counts two positions,
empty artist never clashes and drops the max clause, max per
artist, singular forms, case-insensitive and whitespace-variant
keys count as one artist, summary does not change the order,
end-to-end shuffle over 10 seeds reports 0 clashes, CLI prints
the line, --quiet suppresses it), full suite 408 passed,
0 failed (394 baseline + 14 new). The new test file was run
against the unmodified code first and failed to import, confirming
it tests the new code. UNPROVEN ON A MAC: the summary is pure
Python and was tested here; no Mac run has exercised it, and
`./run.sh shuffle` on a real playlist must not be used as the
spot check, since that shuffles the playlist (the unit tests are
the safe check).

## 2026-11-11 — EXPERIMENTAL: artist keys ignore leading/trailing whitespace (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-10
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost + the 2026-11-06 shuffle repair same-artist skip +
the 2026-11-07 rediscover-preview summary + the 2026-11-08
audit clock fix + the 2026-11-09 audit genre-case fix +
the 2026-11-10 in-memory dedupe kept-set fix). Note for
the publish-time merge: stable has since moved to v3.0.10, which
includes the daily fallback and the menu picker but not the
relative arc, the audit change, the preview change, the artist-key
change, the staged-relaxation fix, the directional-cost fix, the
repair fix, the rediscover-preview summary, the audit clock fix,
the genre-case fix, the kept-set fix, or this fix, so this build
is still a delta on the experimental line, not on stable.

**Why, from the artist key's own job.** The key exists only for
equality comparisons (shuffle/Flow spacing, Rediscover
max-per-artist), and the 2026-11-03 case fix made "Drake" and
"drake" one artist. But rips and taggers also leave stray spaces,
and the key did not strip them: "Drake " and " Drake" were different
keys from "Drake", so those tracks could land back-to-back in a
shuffle or Flow and count separately toward Rediscover's
max-per-artist. The featuring truncation only stripped the tail,
so " Drake feat. X" kept its leading space even after the marker
was cut, and a whitespace-only artist string ("   ") returned a
non-empty key, so it counted as a real artist instead of never
clashing like "" and None. Verified live here before the fix:
artist_key returned 'drake', 'drake ', ' drake', ' drake', and
'   ' for "Drake", "Drake ", " Drake", " Drake feat. X", and
"   " respectively.

**What changed.** `artist_key` in seter_shuffle/artists.py now
strips the raw artist string up front and maps a whitespace-only
string to "". That covers both paths (featuring on and off), since
both return from the stripped name; the marker truncation and its
rstrip are unchanged, and internal spacing is untouched. Only
seter_shuffle/artists.py changed, plus one new test file; no
bridge, run.sh, daily.sh, cli.py, installer, or other file was
touched, and no pick, weight, eligibility, or ordering rule
changed. Tests here: 8 new tests in
tests/test_artist_key_whitespace.py (trailing space is one key,
leading space is one key, featuring truncation strips the leading
space too, featuring-off strips too, whitespace-only is empty,
empty/None still empty, shuffle separates whitespace variants over
20 seeds, Flow separates whitespace variants), full suite 394
passed, 0 failed (386 baseline + 8 new). The 8 new tests were
run against the unmodified code first: 7 failed, confirming they
test the fix and not the old behaviour. UNPROVEN ON A MAC: the
artist-key change is pure Python and was tested here; no Mac run
is needed to prove it, but no Mac run has exercised it either.

## 2026-11-10 — EXPERIMENTAL: in-memory dedupe validation accepts a same-song order when given the kept set (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-09
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost + the 2026-11-06 shuffle repair same-artist skip +
the 2026-11-07 rediscover-preview summary + the 2026-11-08
audit clock fix + the 2026-11-09 audit genre-case fix). Note for
the publish-time merge: stable has since moved to v3.0.10, which
includes the daily fallback and the menu picker but not the
relative arc, the audit change, the preview change, the artist-key
change, the staged-relaxation fix, the directional-cost fix, the
repair fix, the rediscover-preview summary, the audit clock fix,
the genre-case fix, or this fix, so this build is still a delta
on the experimental line, not on stable.

**Why, from the validator's own job.** The safety gate has two
forms of the same dedupe rule: the file form
(`validate_order_file`, the one run.sh and the CLI use) recomputes
the kept set from the dump, and the in-memory form
(`validate_order_text`, for tests and callers that already hold
the IDs). Two different library IDs can be the same song (a
single plus the album version), and dedupe keeps only one of
them, so a correct dedupe order drops the second ID. The file
form accepted that order; the in-memory form only saw IDs, so it
demanded every unique ID exactly once and refused it. Verified
live here before the fix: for a library of A + B (same song as A)
+ C, the file form accepted the dedupe order ["A", "C"] while the
in-memory form refused it with "dedupe order must be exactly the
library's unique songs (each once)". A safety gate that refuses a
correct order is fail-closed, not dangerous, but the two forms
are documented as the same rules, and they were not.

**What changed.** `validate_order_text` in
seter_shuffle/validate.py takes an optional `dedupe_kept_ids`
(the kept set `split_duplicates` computes); in dedupe mode the
check becomes "the order is exactly those kept IDs, each once,
in any order", matching the file form's set rule. Without it the
old ID-level behaviour is preserved and documented, not silently
changed: an ID-only caller cannot know two IDs are the same song.
Dropping a kept song, repeating one, inventing one, or using the
parameter outside dedupe mode still fails exactly as before.
Only seter_shuffle/validate.py changed, plus one new test file;
no bridge, run.sh, daily.sh, cli.py, installer, or other file
was touched, and no pick, weight, eligibility, or ordering rule
changed. Tests here: 8 new tests in
tests/test_validate_dedupe_kept.py (same-song order passes with
the kept set, is refused without it, dropping/repeating/inventing
still refused with it, kept set may reorder, parameter ignored
outside dedupe mode, and the two forms agree on the same
library), full suite 386 passed, 0 failed (378 baseline + 8
new). UNPROVEN ON A MAC: the validator change is pure Python and
was tested here; no Mac run is needed to prove it, but no Mac
run has exercised it either.

## 2026-11-09 — EXPERIMENTAL: audit counts genre strings case-insensitively (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-08
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost + the 2026-11-06 shuffle repair same-artist skip +
the 2026-11-07 rediscover-preview summary + the 2026-11-08
audit clock fix). Note for the publish-time merge: stable has
since moved to v3.0.10, which includes the daily fallback and
the menu picker but not the relative arc, the audit change, the
preview change, the artist-key change, the staged-relaxation
fix, the directional-cost fix, the repair fix, the
rediscover-preview summary, the audit clock fix, or this fix, so
this build is still a delta on the experimental line, not on
stable.

**Why, from the audit's own job.** The audit's top-genres list
exists so the next genre-map edit is driven by real data, but it
counted raw genre strings: "Rock", "rock", and "ROCK" were three
genres, so genre_distinct was inflated and one genre split across
three lines in the list. Flow itself matches genres
case-insensitively (a lowered substring check), so the audit's
counting contradicted how genres are actually used. Verified live
here before the fix: five tracks in two real genres reported
genre_distinct 5, with counts split as Pop 1, ROCK 1, Rock 1,
pop 1, rock 1.

**What changed.** `audit_library` in seter_shuffle/audit.py now
groups genre strings by their lowercased form; the displayed label
keeps the first-seen casing, so the list still reads as the library
wrote it ("Rock", not "rock"). genre_present / genre_missing are
unchanged (presence is still any non-blank string), and the sort
stays count-descending, then label. Only seter_shuffle/audit.py
changed, plus one new test file; no bridge, run.sh, daily.sh,
cli.py, installer, or other file was touched, and no pick, weight,
eligibility, or ordering rule changed. Tests here: 6 new tests in
tests/test_audit_genre_case.py (case variants are one genre with
the first-seen label, mixed case keeps genres separate,
whitespace plus case merges, present/missing counts unchanged,
format_audit lists the merged genre once, CLI audit end-to-end
lists it once), full suite 378 passed, 0 failed (372 baseline + 6
new). UNPROVEN ON A MAC: the merged top-genres list on a real
library dump; it only reads a dump and prints, and the Mac spot
check below is read-only and safe, not proof.

## 2026-11-08 — EXPERIMENTAL: audit's Flow energy range uses the real clock (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-07
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost + the 2026-11-06 shuffle repair same-artist skip +
the 2026-11-07 rediscover-preview summary). Note for the
publish-time merge: stable has since moved to v3.0.10, which
includes the daily fallback and the menu picker but not the
relative arc, the audit change, the preview change, the artist-key
change, the staged-relaxation fix, the directional-cost fix, the
repair fix, the rediscover-preview summary, or this fix, so this
build is still a delta on the experimental line, not on stable.

**Why, from the audit's own job.** The audit exists to explain
Flow behaviour, but its "Flow energies (eligible)" line scored
every track clock-free (`flow_energy` with no reference time),
while Flow itself scores with the real clock (played-date recency
and date-added newness). For a library with recently played or
recently added songs the audit's range was wrong by up to 5 points
against what flowPreview actually builds: a song played 5 days
ago scores 56 in Flow but 53 in a clock-free audit, and a song
added a week ago scores 52 in Flow but 50 in the audit. The
audit's range is the one Spencer reads when deciding whether his
library can actually shape a wave, so it should be the range
Flow builds.

**What changed.** `audit_library` in seter_shuffle/audit.py now
takes an optional `now`; when given, the Flow energies use it
(recency/newness nudges apply), and the CLI `audit` command passes
the real clock. With no `now` the old deterministic behaviour is
unchanged (what the existing tests rely on), and the BPM path
never uses the clock either way, so BPM energies are identical
with or without it. Only seter_shuffle/audit.py and
seter_shuffle/cli.py changed, plus one new test file; no bridge,
run.sh, daily.sh, installer, or other file was touched, and no
pick, weight, eligibility, or ordering rule changed. Tests here:
5 new tests in tests/test_audit_now.py (clock-free audit ignores
recency: 50..53; with a fixed clock the range is 51..56 and
matches prepare_flow's energies exactly at the same reference
time; a BPM track scores the same with or without the clock;
format_audit prints the clock-based range; the CLI audit prints
the clock-based range on a clock-stable fixture), full suite 372
passed, 0 failed (367 baseline + 5 new). UNPROVEN ON A MAC: the
audit line on a real library dump; it only reads a dump and
prints, and the Mac spot check below is read-only and safe, not
proof.

## 2026-11-07 — EXPERIMENTAL: rediscover-preview prints a full-list pick summary (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-06
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost + the 2026-11-06 shuffle repair same-artist skip). Note for
the publish-time merge: stable has since moved to v3.0.10, which
includes the daily fallback and the menu picker but not the
relative arc, the audit change, the preview change, the artist-key
change, the staged-relaxation fix, the directional-cost fix, the
repair fix, or this fix, so this build is still a delta on the
experimental line, not on stable.

**Why, from the same gap the flowPreview summary fixed.** The
2026-11-02 flowPreview arc summary fixed this for Flow, but
rediscover-preview had the same blind spot: it prints only the
first 25 picks, so the first page hid what the full pick list is
actually made of, how much of it was never played at all, how
much is favorited or highly rated, how long the picks were
forgotten, and whether one artist dominates the list.

**What changed.** New `rediscover_summary` in
seter_shuffle/rediscover.py, printed by the CLI for
`rediscover-preview` only, as the last line after the capped
preview list: "Rediscover picks: N songs, X never played, Y
favorited, Z rated 4-5 stars, forgotten A..B days, max C per
artist." The forgotten range uses each pick's last-play (or
added) date and is left out when no pick has a usable date or no
reference time is given; future dates clamp to 0 days rather than
going negative. Picks with no artist string do not count toward
the per-artist max, and the max clause is left out when no pick
names an artist. Featuring counts as the main artist, matching
the 2026-11-03 artist-key rule. The plain `rediscover` command
is unchanged and prints no summary. Only
seter_shuffle/rediscover.py and seter_shuffle/cli.py changed,
plus one new test file; no bridge, run.sh, daily.sh, installer,
or other file was touched, and no pick, weight, eligibility, or
ordering rule changed. Tests here: 11 new tests in
tests/test_rediscover_preview_summary.py (empty returns None,
single song, mixed counts with a hand-checked forgotten range of
184..731 days, no-dates and no-now omit the forgotten clause,
future date clamps to 0, empty artist does not inflate the max,
no named artist omits the max clause, featuring counts as the
main artist, CLI rediscover-preview prints the summary as the
last line over the full 30-song list while showing only 25, plain
rediscover prints none), full suite 367 passed, 0 failed (356
baseline + 11 new). UNPROVEN ON A MAC: the summary line on a real
library dump; it only describes picks already computed, and the
Mac spot check below is preview-only and safe, not proof.

## 2026-11-06 — EXPERIMENTAL: shuffle repair stops wasting tries on same-artist swaps (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-05
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation + the 2026-11-05 Flow directional
cost). Note for the publish-time merge: stable has since moved to
v3.0.10, which includes the daily fallback and the menu picker but
not the relative arc, the audit change, the preview change, the
artist-key change, the staged-relaxation fix, the directional-cost
fix, or this fix, so this build is still a delta on the
experimental line, not on stable.

**Why, from the repair loop itself, not a guess.** The artist
spacing repair pass tries up to 30 random swap partners per clash
and keeps a swap only if it strictly reduces the local clash
count. But swapping two songs by the same artist leaves every
position's key unchanged, so the before/after check always ties
and the swap is always reverted, while the loop still burned a
try and one of the 20,000 global attempts on it. That waste lands
exactly where the pass is already weakest: when one artist
dominates the list, most random partners share that artist, so a
clash could spend all 30 tries on swaps that could never fix it.

**What changed.** `spread_artists` now skips a swap partner by
the same artist as the clashing song (and the trivial j == p
case) without counting it as a try or an attempt, so the 30 tries
go to partners that could actually change the order. Draws per
clash are capped at 300 (10x the try budget) so a degenerate draw
stream cannot spin the loop; an artist owning ~90% of the list
still gets its full 30 effective tries on average. Only
seter_shuffle/shuffle.py changed, plus one new test file; no
bridge, run.sh, daily.sh, installer, or other file was touched,
and Rediscover uses the same repair pass so it gets the fix too.
Tests here: 3 new tests in
tests/test_spread_same_key_skip.py (a scripted draw stream
burying the one useful partner behind 30 same-key draws now
fixes the clash in pass 1 instead of never reaching it, an
always-same-key stream still terminates promptly under the draw
cap, a dominant-artist list never gets worse), full suite 356
passed, 0 failed (353 baseline + 3 new). One hand-verified
trace: with partners [1]*30 + [2] on keys A,A,B,B, the new code
returns [2, 1, 0, 3] in 631 draws, where the old 30-try loop
returned [0, 2, 1, 3]. UNPROVEN ON A MAC: the repair change on
a real library shuffle; it changes only which swaps the pass
tries, and the Mac spot check below runs tests only, not a
playlist.

## 2026-11-05 — EXPERIMENTAL: Flow walk stops jumping ahead of its own arc (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-04
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys + the 2026-11-04
Rediscover staged relaxation). Note for the publish-time merge:
stable has since moved to v3.0.10, which includes the daily
fallback and the menu picker but not the relative arc, the audit
change, the preview change, the artist-key change, the
staged-relaxation fix, or this fix, so this build is still a delta
on the experimental line, not on stable.

**Why, from a real zigzag, not a guess.** The greedy walk's
distance term is symmetric, so on a near-tie it could jump ahead
of the arc on the rise (a hotter song than the target) or drop
below it on the fall (a colder song than the target), making the
actual sequence zigzag around the arc instead of tracking it. The
relative-arc test pinned a case: a rescaled walk ended its
playlist on 80, the hottest song, against a falling tail, because
40 and 80 tied at the second-to-last slot and the tie-break took
the earlier song. The sequence tracked the arc on distance but
not on direction.

**What changed.** Each walk step now adds a small +5 when a
candidate sits on the wrong side of the arc target for the arc's
direction at that position: above the target while the arc is
rising, below it while the arc is falling. The direction comes
from the arc targets themselves (next target vs current, previous
target at the last slot), so the peak slot counts as falling and
prefers not to undershoot the peak. +5 only breaks near-ties: a
candidate 6+ closer to the target still wins, artist spacing
(1000) still wins over everything, and a flat pool is unaffected
because equal energies are penalised equally. Only
seter_shuffle/flow.py changed (the new `_arc_direction` helper
and the cost term), plus one new test file and one updated
expectation in test_flow_relative_arc.py; no bridge, run.sh,
daily.sh, installer, or other file was touched. Tests here: 10
new tests in tests/test_flow_directional_cost.py (direction
helper including the rescaled arc and last-slot arrival
direction, rise/fall/peak near-ties, closer match still wins,
flat pool unchanged, spacing still beats the penalty,
prepare_flow end-to-end), full suite 353 passed, 0 failed (343
baseline + 10 new). One existing expectation changed by hand
after verifying the new order tracks the arc better (total arc
distance 33 vs 53, and the walk now ends on the coldest song
instead of the hottest). UNPROVEN ON A MAC: the walk change on
a real library dump; it changes only the order Flow picks, and
the Mac spot check below is preview-only and safe, not proof.

## 2026-11-04 — EXPERIMENTAL: Rediscover relaxes its variety rules one at a time (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-03
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary +
the 2026-11-03 case-insensitive artist keys). Note for the
publish-time merge: stable has since moved to v3.0.10, which
includes the daily fallback and the menu picker but not the
relative arc, the audit change, the preview change, the
artist-key change, or this fix, so this build is still a delta
on the experimental line, not on stable.

**Why, from a real small-pool case, not a guess.** Rediscover
picks under two variety rules: at most N songs per artist, and
no song picked within the cooldown window. When the pool was
too small to fill the target under both rules, the picker fell
straight to a pass enforcing neither rule, so a slot could be
filled by a song picked two weeks ago even when an extra song
by an already-picked artist would have filled it, and a slot
could break the artist cap even when a cooldown repeat would
have. The cooldown is the point of Rediscover (do not repeat
recent picks), so it should be the last rule broken, not the
first one broken alongside the cap.

**What changed.** `pick_rediscover` now relaxes one rule at a
time, in this order: (1) both rules enforced, (2) cooldown
enforced, artist cap relaxed, (3) artist cap enforced,
cooldown relaxed, (4) neither enforced, and only then the
existing front-of-list fill. The sampler's single
`enforce_rules` flag became two independent flags
(`enforce_history`, `enforce_artist`); no weight, eligibility,
target, ordering, or history-recording rule changed, and a pool
that can fill under both rules behaves exactly as before.
This refines v2.6's single relaxed pass (both rules dropped at
once) by keeping that pass as the last resort only. Only
seter_shuffle/rediscover.py changed, plus one new test file;
no bridge, run.sh, daily.sh, installer, or other file was
touched. Tests here: 4 new tests in
tests/test_rediscover_staged_relaxation.py (cap relaxes before
any cooldown repeat, cooldown relaxes before the cap breaks
twice, both relax only as a last resort to fill the playlist,
strict pool still respects both rules), full suite 343 passed,
0 failed (339 baseline + 4 new). UNPROVEN ON A MAC: the staged
passes on a real library; they only fire when a pool cannot
fill under both rules, so a normal-size library preview will
likely never reach them, and the Mac spot check below is
preview-only and safe, not proof.

## 2026-11-03 — EXPERIMENTAL: artist keys are case-insensitive (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-02
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts + the 2026-11-02 flowPreview arc summary). Note
for the publish-time merge: stable has since moved to v3.0.10,
which includes the daily fallback and the menu picker but not the
relative arc, the audit change, the preview change, or this fix,
so this build is still a delta on the experimental line, not on
stable.

**Why, from a real mismatch, not a guess.** The artists module
always documented case-insensitive matching (the AppleScript
behaviour), but the Python port compared keys with ==, so the
same artist spelled differently across rips ("Drake" vs "drake")
counted as two different artists. That defeated artist spacing in
shuffle and Flow and the max-per-artist count in Rediscover, all
three of which go through artist_key.

**What changed.** artist_key now returns a lowercased key. The key
is used only for equality comparisons, never displayed, so no
output text changes; only which tracks count as the same artist.
Three existing test expectations in test_core.py were updated to
the lowercased keys (they asserted the old case-preserving return).
No bridge, run.sh, daily.sh, installer, or other file was touched.
Tests here: 6 new tests in tests/test_artist_key_case.py (same
artist in three cases is one key, featuring markers still
case-insensitive, featuring-off still lowercases, empty/None
still empty, shuffle separates case variants across 20 seeds,
Flow greedy walk separates a case-variant repeat), full suite
339 passed, 0 failed (333 baseline + 6 new). UNPROVEN ON A MAC: the spacing change on a
real library dump; it changes no playlist by itself, and the Mac
spot check is `./run.sh rediscover-preview`, which prints picks
and writes nothing.

## 2026-11-02 — EXPERIMENTAL: flowPreview prints a full-list arc summary (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-11-01
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback + the 2026-11-01 audit
same-song counts). Note for the publish-time merge: stable has
since moved to v3.0.10, which includes the daily fallback and
the menu picker but not the relative arc, the audit change, or
this preview change, so this build is still a delta on the
experimental line, not on stable.

**Why, from a real preview limit, not a guess.** flowPreview
prints only the first 25 songs (preview_show), so a flat first
page used to hide whether the full 50-song Flow order actually
rises and falls. Spencer's 2026-10-28 preview came back flat
for exactly that reason, and the fix then was judged on the
first 25 energies alone.

**What changed.** `./run.sh flowPreview` now prints one extra
line after the preview list, covering the whole ordered list:
"Flow arc: N songs, energies lo..hi, starts X, peaks Y at
#P, ends Z." The peak position is the first position at the
maximum energy. The plain `flow` command does not print it,
so its JSON output is unchanged, and `--quiet` still prints
nothing. Only seter_shuffle/flow.py (the new
`flow_arc_summary` helper) and seter_shuffle/cli.py (print it
for flowPreview only) changed, plus one new test file.
Tests here: 7 new tests in
tests/test_flow_preview_arc.py (empty, single song, rise and
fall, flat list, tied peak, CLI flowPreview end-to-end with
the summary as the last line, plain flow with no summary),
full suite 333 passed, 0 failed. UNPROVEN ON A MAC: the
summary line on a real library dump; it describes an order
already computed and changes no playlist, so the Mac test is
preview-only and safe.

## 2026-11-01 — EXPERIMENTAL: audit counts same-song library copies (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. Base is the 2026-10-31
experimental staging (v3.0.9 + the 2026-10-30 Flow relative arc +
the 2026-10-31 daily dedupe fallback). Note for the publish-time
merge: stable has since moved to v3.0.10, which includes the
daily fallback and the menu picker but not the relative arc and
not this audit change, so this build is still a delta on the
experimental line, not on stable. Only seter_shuffle/audit.py
changed, plus one new test file; no bridge, run.sh, daily.sh,
installer, or other file was touched.

**Why, from a real confusion, not a guess.** On 2026-10-29 a
Mac run log showed the main playlist at 806 unique songs where
Spencer expected 798: 12 entries were the same song stored as a
different library track, and only the dedupe log explained the
gap. The audit command is the tool for "is my data what I
think it is", but it counted library tracks only, so a library
holding the same recording twice (single + album, matched +
uploaded) looked like more distinct songs than it holds, and a
dedupe total landing below the library size looked like songs
going missing.

**What changed.** `audit_library` now reports two extra
counts, computed with the exact same conservative rule dedupe
uses (same artist + title after normalisation, lengths within
3 seconds when both are known; titles never trimmed of
"(Live)" or "- Remastered"; no-artist tracks never matched by
name): `same_song_groups` (how many songs have 2+ library
copies) and `same_song_extra` (extra copies beyond the first).
A repeated persistent ID is a dump error, not a library copy,
and is never counted here. `format_audit` prints one line
with both numbers, so `./run.sh audit` (via the CLI audit
command) answers the question directly. Tests here: 10 new
tests in tests/test_audit_same_song.py (three-copy group,
two groups, different artist, different lengths, live suffix,
case/whitespace normalisation, missing artist, same-ID repeat
excluded, zero case, and a CLI end-to-end run), full suite
326 passed, 0 failed. UNPROVEN ON A MAC: the audit line on a
real library dump; the counts use only fields already in the
dump, so no bridge change was needed.

## 2026-10-31 — EXPERIMENTAL: daily dedupe fallback for all three targets, on top of v3.0.9 + the 2026-10-30 Flow relative arc (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. This build INCLUDES the
2026-10-30 Flow relative arc (which was prepared but never
published, so no exp-2026-10-30.* tag exists to supersede on
GitHub; this build supersedes that unpublished staging copy
only). The base is the published v3.0.9 stable tree; against
that base, the code changed is daily.sh plus tests, plus the
2026-10-30 flow.py change. No bridge script, run.sh,
installer, or other stable file was touched.

**Why, from a real run, not a guess.** On 2026-10-31 the
v3.0.9 daily run (10:21-10:24 PT) deduped the tripled main
playlist in place (2386 entries to 798), then hit the
SeTeR Rediscover probe's duplicate refusal at 10:24:05 and
exited, because daily.sh only had the duplicate-fallback
dedupe path for the main playlist probe and did
`auto_self_probe || exit 1` for Rediscover and Flow. So
shuffle, flow, and rediscover never ran that morning, and
neither did their description stamps. The v3.0.9 header
even stated the gap plainly ("a doubled generated playlist
is a manual dedupe, not a daily-run repair"); the Oct 31
run proved that manual-repair rule costs a whole daily run.

**What changed.** daily.sh gained one helper,
`probe_target`, used for all three targets in the same
order as before (daily playlist, Rediscover, Flow). On a
probe that refuses ONLY on duplicate entries (wording
checked, never the exit code alone), it runs one in-place
dedupe for that target (the v3.0.9 repair: snapshot
before, verified after, deletes only duplicate entries in
descending position order, 0 rebuilds on success, no
mapping recorded), then re-probes the clean target ONCE
for a fresh mapping. The re-probe is safe against the
shared-snapshot rule: the refused probe changed nothing
and wrote no snapshot, and the re-probe is on the same
target, never a different target while a restore is
pending. The main playlist gets the re-probe too now,
instead of relying on a mapping that survived the refused
probe for the later mapping check. Any other probe
failure, a failed dedupe, or a re-probe that still
refuses or fails stops the whole daily run before the
next target is probed and before any build, with exactly
one dedupe attempt per target and no second attempt. No
cross-target mapping, no throwaway probe, no other
fail-closed rule was weakened.

**Tests here:** full suite in this staging copy, 316 tests
passed, 0 failed (309 in the 2026-10-30 staging + 7 new in
tests/test_daily_dedupe_fallback.py: Rediscover and Flow
duplicate probes each dedupe, re-probe, and complete the
daily run; main now re-probes after its dedupe; a failed
dedupe stops before the Flow probe and before any build;
a failed re-probe and a still-duplicate re-probe each stop
with exactly one dedupe attempt; plus a structural test
that probe_target is the only probe path). Two existing
tests were updated for the intentional behavior change,
not weakened: the main-duplicate daily test in
tests/test_trial_dedupe.py now pins the re-probe call,
and the probe-before-check structural test in
tests/test_selfprobe.py now pins probe_target. Shell
syntax and py_compile pass; no Python core or bridge file
changed for this improvement.

**Known limits, plainly.** UNPROVEN ON A MAC: the fallback
for Rediscover and Flow, and the re-probe after any
fallback dedupe, are proven only with stubbed run.sh calls
here. They are not proven until a real daily run on his
Mac hits a doubled Rediscover or Flow playlist and
completes shuffle, flow, and rediscover with that
morning's stamps. If a re-probe ever measures a different
mapping than the pre-doubling one (it should not: in-place
dedupe does not change a playlist's sort), verify-after
still fails closed on the build, never a corrupted order.

## 2026-10-30 — EXPERIMENTAL: Flow relative arc, on top of stable v3.0.9 (not a stable release)

Experimental only, prerelease if published, never auto-installed,
never merged into main as stable. This is the 2026-10-29 held
build, finally ported: it was prepared 2026-10-29 evening in a
separate staging copy and never published (tag conflict that
night), and it is NOT in stable v3.0.9. The base for this build
is the published v3.0.9 stable tree; the only code changed
against that base is seter_shuffle/flow.py, plus one new test
file. No bridge script, run.sh, daily.sh, installer, or other
stable file was touched for it.

**Why.** Spencer's 2026-10-29 audit showed a real library with
BPM missing on 100% of tracks and Flow fallback energies
spanning only 47..68. The fixed 45..90..40 arc therefore aims
at a peak (90) the pool cannot reach and a tail (40) below
its floor: the walk climbs toward 90 and stops at the closest
available song each step, instead of shaping a wave inside
the range the pool actually has.

**What changed.** `flow_order` takes optional `arc_lo` /
`arc_hi`; when both are given and the range is at least 10,
each fixed arc target is rescaled as
lo + (fixed - 40) / 50 * (hi - lo), so the fixed start (45)
lands near the pool floor, the fixed peak (90) lands on the
pool max, and the fixed end (40) lands on the pool floor.
`prepare_flow` passes the pool's own min/max only when every
pool track is BPM-missing and the range is at least 10. A
pool with any BPM track keeps the fixed arc exactly, so BPM
scoring stays byte-for-byte the AppleScript behaviour, and
a narrow fallback range (<10) keeps the fixed arc rather
than amplifying noise. Existing `flow_order` callers without
the new arguments behave exactly as before.

**Tests here:** full suite in this staging copy, 309 tests
passed, 0 failed (303 in the v3.0.9 base + 6 new in
tests/test_flow_relative_arc.py: arc scaling math, fixed-arc
behaviour without bounds or with a narrow range, rescaled
vs fixed walk on the same pool, a fallback pool rising and
falling inside its own range with its peak near the pool
top, a BPM pool keeping the fixed arc, and a narrow
fallback pool keeping the fixed arc). Shell syntax and
py_compile also pass; no shell or bridge file changed.

**Known limits, plainly.** UNPROVEN ON A MAC: the relative
arc is proven only on synthetic pools here. It is not proven
against Spencer's real library until he runs flowPreview on
a Mac and the first 25 show a rise and fall inside the
pool's own energy range. A library with only calm songs
will still sound calm overall; the wave is relative, not
louder. Flow preview changes nothing, so that Mac step is
safe to try without touching any playlist.

## 2026-10-29 — v3.0.6: same-song dedupe by default, plus setup fixes

Dedupe now removes a song stored as a different library
track, not just an exact-ID repeat: same artist + title
after case/accent/space normalisation, and within 3 seconds
of length when both lengths are known. The bridge dump now
carries duration in integer milliseconds, so the length
check has data. Titles are never trimmed, so "Song (Live)"
or "Song - Remastered" are different songs, and a track
with no artist or no title is matched by ID only. The
first copy in the playlist stays, and only playlist
entries are removed; nothing leaves the library. To go
back to exact-ID matching only:
`SETER_DEDUPE_MATCH=id ./run.sh dedupe "Playlist"` (for
the daily run, add it to the launchd plist's
EnvironmentVariables). The Rediscover picker also gives
one slot to a song that exists twice in the library.
Tradeoff, stated plainly: same artist + title within 3
seconds merges, first copy stays, and a dump with unknown
durations merges on names alone.

Also in v3.0.6: setup fixes (warn() prints its message;
re-running setup from the installed copy no longer hits a
same-file copy error; uninstall refuses a directory that
is not a SeTeR install); the installer final note now
states the daily self-probe behaviour instead of the stale
manual sortprobe instruction; daily.sh drops an unused
history variable.

Version marker bumped to `3.0.6`; no v2.6 file was changed.
UNPROVEN ON A MAC: the v3.0.6 one-click run, same-song
dedupe on a real playlist, trial-dedupe completing on the
real doubled playlist, the mapping recorded by a
successful trial, and a subsequent shuffle after
trial-dedupe.

## 2026-10-29 — v3.0.5: restores try both mappings before declaring CRITICAL (NOT yet a published release)

On 2026-10-29 18:59-19:05 PT Spencer ran trial-dedupe
(v3.0.4) on the real main playlist from the menu: 1612
entries, 806 unique songs, first-occurrence order
computed and logged, then the forward trial apply
verified-failed. That part was correct: the playlist's
true mapping is reversed, so a forward build cannot land
the deduped order. The trap was the restore: apply-order
rebuilt the pre-dedupe snapshot with the SAME forward
mapping, so it verified-failed too and declared CRITICAL,
and the run.sh undo restore failed the same way. The
pre-undo snapshot file proved the playlist held all 1612
entries at undo start, in the exact reverse of the
snapshot, and a read-only diagnostic at 19:08 PT proved
the current list-read order is exactly the pre-dedupe
snapshot order (1612, first EC60833070C7D0B1, last
6471F2089E4E7F7D). No songs were lost, and the playlist
is back at doubled order and needs no restore. Do NOT
re-run trial-dedupe on v3.0.4: it would repeat the same
forward-then-restore trap.

**What changed.** Every restore now tries BOTH mappings
before declaring CRITICAL: bridge/apply-order.applescript
(its internal restore after a failed build, a
delete-empty failure, and a library shrink), bridge/
undo.applescript (its pre-undo restore), and
bridge/restore-original.applescript (its snapshot
put-back, the same trap in the run.sh restore path).
Each attempt is verified against the snapshot it is
returning to; the first verified attempt wins, and only
if neither verifies does the script declare CRITICAL
with the snapshot named. This is NOT a build flip and
must not be misread as one: a failed build still exits
non-zero and records nothing, and the opposite mapping
is never used to land a desired order. A restore retries
only to return to a known snapshot that already existed.
In run.sh, a trial-dedupe attempt whose restore fails
now means neither mapping restored, so the trial stops
critical with the snapshot named and does not try the
other trial mapping on top of a possibly partial state;
if the restore succeeds under either mapping, the trial
proceeds to the next mapping as before.

Version marker bumped to `3.0.5`; no v2.6 file was changed.
UNPROVEN ON A MAC: the v3.0.5 one-click run, trial-dedupe
completing on the real doubled playlist, the mapping
recorded by a successful trial, and a subsequent shuffle
after trial-dedupe.

## 2026-10-29 — v3.0.4: trial-dedupe breaks the doubled-playlist deadlock (NOT yet a published release)

On 2026-10-29 18:44 PT Spencer ran the v3.0.3 menu on the
real main playlist and the auto self-probe refused on
duplicate entries (1612 entries, 806 unique), target
untouched, no dump or apply. Dedupe needs a mapping, and
the probe cannot measure one on a doubled playlist. That
deadlock is what this release breaks, without weakening
the probe.

**What changed.** `./run.sh dedupe` (menu choice 3 and
direct) no longer probes first. A clean playlist applies
nothing and needs no mapping. A fresh mapping, when one
exists, is used directly with no trial. Otherwise dedupe
trial-applies its known desired order (first occurrence
of each song in list-read order, with one "Removed
duplicate" line per removed entry as before): forward
first, verify the list read against the deduped order,
and on failure restore from the per-run snapshot and try
reversed. The first mapping that verifies wins and is
recorded as a trial-dedupe mapping, so the next build
reuses it directly. If neither verifies, the playlist is
restored to its pre-dedupe order, no mapping is recorded,
and dedupe exits non-zero. If an attempt's restore itself
fails critically (playlist possibly partial), the trial
stops immediately and does not try the other mapping on
top of a partial state; the per-run snapshot is named in
the log. The daily run attempts trial-dedupe only when
the daily playlist's probe refused on duplicate entries
specifically (the probe output wording is checked, not
just the exit code); any other probe failure still stops
the daily run immediately, and a failed trial-dedupe stops
it before shuffle/rediscover.

**Snapshot/undo guarantee.** Every trial attempt writes
its own per-run snapshot before any change (the filename
now also carries $RANDOM, so two attempts in the same
second cannot share a snapshot file), and the main backup
is installed only after a verified successful dedupe, with
the previous main backup preserved as .prev. Undo after a
successful trial-dedupe therefore returns to the doubled
pre-dedupe order.

**Probe refusal, unchanged.** sortprobe/selfprobe on a
doubled playlist still refuse and change nothing. The
mapping oracle in trial-dedupe is verify-after on the
actual desired deduped order, not a rotation
classification, and this path must never be borrowed back
into the probe.

Version marker bumped to `3.0.4`; no v2.6 file was changed.
UNPROVEN ON A MAC: the v3.0.4 one-click run, trial-dedupe
on the real doubled playlist, the mapping recorded by a
successful trial, and a subsequent shuffle after
trial-dedupe.

## 2026-10-29 — v3.0.3: automatic self-probing for menu and direct builds (NOT yet a published release)

v3.0.2 only auto-probed the daily run. Spencer then ran the
menu on 3.0.2 and still got the gate failure, correctly,
because the menu code explicitly said it "never probes" and
called mapping_ready_for || continue. That is the gap this
release closes: probing is now automatic for menu and direct
builds too, not just the daily run.

**What changed.** `run.sh` gained ensure_mapping_for, called
before any dump or apply by menu choices and by direct
shuffle, rediscover, dedupe, flow, undo, and restore. A
fresh (<48h), correctly-targeted, forward/reversed mapping
is reused as-is, with NO re-probe, so a normal run costs no
extra rebuild. A missing, stale, or otherwise unusable
mapping triggers `./run.sh selfprobe` on the target itself,
then a re-check; if it is still not ready after the probe,
the run aborts with the probe error named, before any dump
or apply, and the menu loops back. Gate-failure messages no
longer tell the user to run a manual sortprobe first when
the automatic self-probe just failed; they name the
self-probe that was attempted. Manual sortprobe and
selfprobe commands keep working exactly as before.

**Safety, unchanged.** The probe snapshots first, rotates,
restores under the measured mapping, and verifies the
restore; "other" aborts and deletes the mapping; the
duplicate-entry refusal is unchanged, so a doubled playlist
still fails closed at the probe, documented plainly;
verify-after still fails closed; no other target's mapping
is ever borrowed; no fresh throwaway probe is ever used.
The v3.0.2 restore-failed exception still applies inside
the probe itself (mapping recorded so restore can run,
probe exits non-zero, no build follows).

Version marker bumped to `3.0.3`; no v2.6 file was changed.
UNPROVEN ON A MAC: the v3.0.3 one-click run, a menu
auto-probe on a real playlist, a direct-build auto-probe,
and the doubled-playlist dedupe deadlock path.

## 2026-10-29 — v3.0.2: automatic self-probing (NOT yet a published release)

Spencer's correction, which supersedes the throwaway-only
rule for sortprobe: Apple Music remembers each playlist's
own sort, so probe the actual target playlist itself, not a
different throwaway. He is right, and the earlier ban was
over-cautious for sortprobe specifically (it still holds for
test shuffles: never shuffle a real playlist as a test). A
mapping measured on the target under its own sort is, by
construction, the mapping for that target and sort, so no
throwaway sort needs matching and no mapping transfer is
possible.

**What changed.** `./run.sh selfprobe <playlist>` (and
`sortprobe` with throwaway == target, which is the same
self-probe) snapshots the target, builds a rotation, restores
the snapshot under the measured mapping, and verifies the
restore before returning OK; it records THROWAWAY as the
target name and SORT as "self-probe: target's own sort".
`daily.sh` now auto self-probes the daily playlist AND
"SeTeR Rediscover" before the mapping check, so the 48-hour
manual-probe chore is gone; the mapping gate is NOT dropped
(a failed self-probe fails the whole daily run closed before
any build, before probing the other target, because the two
probes share one snapshot file; an "other" mapping still
aborts). One deliberate exception to "a failed probe deletes
the mapping": a probe that measured forward/reversed but
could not verify its own restore RECORDS that mapping, so
`./run.sh restore <target> <snapshot>` can run, while the
probe still exits non-zero and no build follows until the
target is restored and a clean probe passes. Every other
probe failure still deletes the mapping.

**Deadlock, stated plainly.** The duplicate-entry refusal is
unchanged: a self-probe on a playlist with duplicate entries
refuses and changes nothing. A currently doubled playlist
(the main playlist was 1612 entries / 806 unique on
2026-10-29) therefore cannot be auto-probed until it is
deduped by hand, or under a mapping obtained another way.
The refusal is NOT weakened to work around this. Version
marker bumped to `3.0.2`; no v2.6 file was changed. UNPROVEN
ON A MAC: the v3.0.2 one-click run, a self-probe on a real
playlist, the daily auto-probe on a Mac, and the
doubled-playlist dedupe deadlock path.

## 2026-10-29 — v3.0.1: one-click installer fix (NOT yet a published release)

Proven on Spencer's Mac at ~17:32 PT, running the v3.0 one-click
installer with no extra arguments: after "ok python3 check
passed" and "Step 1 of 3: installing/updating…", it died with
"install-or-update.sh: line 147: SETUP_ARGS[@]: unbound
variable". Same bash 3.2 empty-array class as the .7 menu bug:
macOS ships bash 3.2, where expanding an empty array under
set -u is an error, unlike bash 5 on Linux, so the bug was
invisible here. The installer stopped at Step 1, before any
migration, so v2.6 and the existing install were untouched.

**Fix.** `install-or-update.sh` contains no array at all now:
setup arguments are rebuilt with `set --` / `"$@"`, which is
safe when empty even on bash 3.2, and `--force` is always
passed through (the user already confirmed once in the
one-click script), so an update from a `3.0-proposed` or `3.0`
install is allowed. A tree-wide audit found only one other
`[@]` expansion, `apply_args` in `run.sh`, which is assigned
all 7 elements in both branches before use and is provably
non-empty, so it was left alone. The installer also chmods +x
its own helpers at the start of every run, because the v3.0 zip
shipped them mode 660 and double-clicking gave "permission
denied". Installer marker bumped to `3.0.1`; no v2.6 file was
changed. UNPROVEN ON A MAC: the v3.0.1 one-click run itself,
including the no-argument path and the stripped-modes path.

## 2026-10-29 — v3.0 stable-prep: one-click install-or-update (NOT a published release)

Spencer approved publishing v3.0 stable and asked for almost a
one-button click to install or update everything. This entry is
the code preparation for that publish, not the publish itself:
no v3.0 tag or release is created by this tree, and the parent
publishes after verifying the main-branch push.

**What was added.** `install-or-update.sh` (also shipped at the
repository root, plus a double-clickable
`SeTeR-Shuffle-Install.command` wrapper in both places): one
confirmation prompt, then, in order, a real-python3 check,
install or update of `~/Documents/SeTeRShufflePython` to v3.0
(differing files get a timestamped `.bak` first; setup is run
with `--force` so an update from a `3.0-proposed` experimental
install is allowed), the 8:00 AM `com.seter.python.daily`
plist written and loaded, `migrate-to-python.sh --dry-run`
then `--confirm` only if the v2.6 daily job is still enabled,
and a final verification (install dir present, Python plist
present, v2.6 plist gone). Any failure stops before migration
and prints the rollback command. Update mode re-runs migration
only if v2.6 is still enabled. The installer marker is now
`3.0` (was `3.0-proposed`); `setup-python.sh` also copies
`install-or-update.sh` into the install dir.

**What it deliberately does not do.** It does not auto-probe:
the 8am daily run still refuses without a fresh (<48h)
per-target mapping for the main playlist and Rediscover, so
the tool prints the exact sortprobe reminder at the end, and
the user must probe each target on a clean throwaway (never
the main playlist itself) before the first scheduled run. It
never deletes or edits the v2.6 script, backups, apps, or
Rediscover history.

**Still unproven on a Mac.** The one-click run itself,
migration via one-click, the first scheduled daily run, and
the still-open items from earlier entries (throwaway
checklist, flow undo, the library-drop investigation).

## 2026-10-29 — Menu bug fix (bash 3.2 empty-array crash, pre-dump mapping gate)

Spencer's Mac paste, 17:01 PT, from the .6 folder: `./run.sh
menu`, choice 1 Shuffle, playlist "My New Sandwich Recipe",
size blank (all). Dump playlist succeeded (1612 songs), then
run.sh died with an unbound-variable error at the shuffle
compute step, before any compute or apply. No playlist change
happened; the run aborted cleanly but uselessly, after a
wasted dump.

**Root cause, proven not guessed.** macOS ships bash 3.2,
where expanding an empty array under `set -u` is an
unbound-variable error, unlike bash 5 on Linux where it
expands to nothing. The shuffle path built an empty size
array for a blank size and then expanded it, and the menu
path had the same shape (a blank playlist plus a blank size
also meant an empty menu argument array). The bug was
invisible here because this machine runs bash 5.

**What changed.** Both arrays are gone. The shuffle compute
block now spells out its full argument list branch by branch
(blank/all passes no size flag; a set size passes exactly
one), and the menu shuffle dispatch does the same for its
four playlist/size combinations. The only array expansion
left in run.sh is apply_args, which is always assigned
exactly seven elements before use. Daily, setup, and
migration scripts were audited for the same pattern and
have no array expansions. An existing drop-in test
assertion that named the old array variable was updated to
the new branch spelling; nothing was weakened.

**Related menu gap, fixed in the same build.** The same
paste showed the menu printing "mapping status: none
recorded" and then dumping anyway, because the mapping gate
only fired at apply time. The menu now pre-checks with
mapping_ready_for before invoking any build: a missing,
stale (>48h), non-forward/reversed, or sort-label-less
mapping refuses with the exact sortprobe command and the
menu loops back, before any dump. Flow preview and audit
need no mapping and are unchanged. The non-interactive
dedupe refusal in the same paste (1612 entries / 806
unique, then GATE FAILED on the missing mapping, no change
applied) was correct and is unchanged; non-interactive
paths still dump first and refuse at apply time.

**Still unproven on a Mac, plainly.** This build has never
run on a Mac: the bash 3.2 fix is reasoned from the macOS
bash version and the exact pasted error, not observed on
bash 3.2 here, and the menu pre-check needs a Mac run
(menu shuffle with a blank size, and menu shuffle with no
mapping must refuse before any dump).

## 2026-10-29 — Flow energy fix (arc-first walk, finer vibe score)

Spencer authorized fixing Flow flatness by any offline means, on
branch experimental only: no merge to main, no stable release, no
tag created for this work, nothing ran on his Mac, no API key, no
network code, no invented tempo.

**Root cause, proven from his runs, not guessed.** Two causes
stacked. (1) The fallback score gave nearly every low-play gospel
track the same inputs: same genre group (-2), same coarse play
tier, unrated, not favorited, BPM missing, so they all scored
47-50. (2) The walk's genre cost (0 same / 8 related / 20
otherwise) outweighed the whole energy distance, so the walk
stayed inside the gospel cluster at one energy for the first
half and then jumped to a different cluster at the peak: a
16-long run of exactly 50 on a gospel-heavy synthetic profile
mirroring his library, then a cliff to 72-77. A flat block plus
a jump is not a wave.

**What changed, in plain words.** The score is now explicitly a
vibe/arc score, never a tempo, when BPM is missing. The
BPM-present path is untouched (same bands, same legacy nudges,
same plays step, same rating/favorited terms, and no new term
touches it, so BPM scores are byte-for-byte unchanged). The
fallback now uses only fields already in the library dump:
finer play tiers (0/1/2/3/4/6/8/10/12 instead of 0/2/4/6/9);
genre raw-string subgroups inside group 8 (choir/choral -4,
worship/praise -2, contemporary +3, on top of the -2 group
nudge; "Choir"/"Choral" are now also mapped to group 8, where
before they fell through to "anything else"); finer skip bands
(>90% skips -8, >50% -5, 25-50% -2, never-skipped well-played
+2); a release-year era band (2020+ +2, 2010s +1, 2000s 0,
1990s -1, older -2); and, when the caller supplies a clock
(prepare_flow uses the real clock, tests use a fixed clock),
played-date recency (last 30 days +3, 31-180 days +1, over
730 days -2) and date-added newness (last 90 days +2). No new
dump field was added: duration is not in the dump and was not
invented. The walk is now arc-first: genre cost 0/3/8, year
cost 0/2/4, plus +4 for repeating the exact previous energy,
so the arc target drives the walk and genre continuity only
breaks near-ties. Artist spacing still wins over vibe.

**Synthetic gospel-heavy before/after (same 260-track profile,
200 low-play gospel/Christian + 60 higher-play hip-hop/pop,
all BPM missing, flow_size 50, seed 42).** Before: first 25
energies 45-50 for the first 19 positions, 6 distinct values,
a 16-long run of exactly 50, then a cliff to 72-77. After:
first 25 energies rise 45, 46, 48, 49, 51, 52, 53 ... 78, 16
distinct values, longest run of any one energy 1, peak band
(positions 20-33) mean 76.8 vs first-10 mean 50.1, tail
falling to 42. The step from the gospel cluster to the
higher-energy cluster is still visible (gospel tracks top
out around the mid-50s, so the arc must leave the cluster to
reach the peak); it is now a climb through the 60s and 70s,
not a single jump.

**Pinned fallback values changed by design.** The year band
moves four old pinned values: blank song 50 -> 52, gospel-never
48 -> 50, ambient-never 38 -> 40, mostly-skipped rock 55 -> 57.
BPM pinned values are unchanged. Four old tests were updated
to the new arithmetic; nothing else in the suite was weakened.

**Still unproven on a Mac:** this fix is proven only on a
synthetic gospel-heavy library here. It is NOT proven against
Spencer's real library until he runs flowPreview on a Mac and
the first 25 show a rising arc instead of a flat 47-50 block.
That Mac step is now Step 10d in STABLE-PROMOTION-TESTS.md.
Flow energy tuning is no longer an open gap in the drop-in
list, but it stays open until that Mac run.

## 2026-10-29 — Drop-in replacement package (48h mappings, menu, stamp, notifications, size, dedupe names)

Spencer ordered the stable-prep gaps closed, on branch experimental
only: no merge to main, no stable release, no tag created for this
work, nothing ran on his Mac. Each gap from the stable-prep audit
is closed below, except Flow energy tuning, which is left open
deliberately (see below).

**1. Mapping validity 24h -> 48h, everywhere.** `run.sh`
`mapping_for_build`, `daily.sh` `check_mapping`, sortprobe's
recorded validity, and every doc error message now use 172800
seconds. Rationale, documented in `daily.sh`: an evening
sortprobe now covers the next TWO mornings' 8am daily runs, and
verify-after still fails closed if the sort actually changed in
the window, so a stale mapping costs a refused run, never a
corrupted playlist. Nothing else weakened: per-target files,
TARGET field, sort label, forward/reversed only, no auto-probe,
no cross-target fallback.

**2. Interactive menu.** `./run.sh menu` is a Terminal menu
matching v2.6's interactive options: shuffle a playlist,
rediscover, dedupe, undo, flow, flowPreview, audit. It prompts
for the playlist name (and size for shuffle), prints the
recorded mapping status for the chosen target before building,
and re-invokes run.sh as a fresh process for every choice, so
every gate applies unchanged. It never probes and never
overrides a refusal. No .app bundle is required or built; the
menu is Terminal-based, and that is stated, not hidden.

**3. Last-reshuffled stamp.** After a verified successful
shuffle or flow apply, `apply-order.applescript` sets the
target playlist's description to "Last reshuffled: <local
date/time>". The stamp runs only after verification and the
library-shrink check pass, only when run.sh passes the stamp
flag (shuffle/flow only), and never for undo, restore, dedupe,
or rediscover. It is best-effort: if Music's scripting does
not expose a settable playlist description, the stamp step
logs skipped and the already-verified apply still succeeds.
Whether Music exposes a settable description is unproven on a
Mac (like every bridge change here).

**4. Notifications.** `run.sh` and `daily.sh` send a macOS
`display notification` on success and on failure (playlist
name, or the gate reason), in addition to logs. Notifications
are best-effort: a missing osascript or denied Notification
Center permission logs "notification unavailable" and never
fails the run.

**5. Library size wiring.** `./run.sh shuffle [playlist]
[size]` and `SETER_SHUFFLE_SIZE` now pass `--size` to the CLI
(100/250/500/1000/all; blank/all = whole library, the daily
default). Size applies ONLY to a whole-library shuffle into
the generated "SeTeR Shuffle" playlist: a sized in-place
shuffle would drop songs, so run.sh refuses it before any
dump, and a size-capped order validates under a new
"shuffle-size" mode (presence/multiplicity only) instead of
the exact-multiset "shuffle" mode it would rightly fail.

**6. Dedupe name logging.** The CLI `dedupe` command now
prints one "Removed duplicate: <artist> - <name>" line per
removed entry (names from the dump itself), so the run log
identifies every removed entry. Dedupe still applies nothing
when clean and still preserves first-occurrence order.

**7. Flow energy: NOT changed, deliberately.** A gospel-heavy
synthetic library (BPM missing, varied plays/ratings) already
spreads 47-67 across 9 distinct values in the current model;
Spencer's real first-25 flatness (47-50) comes from most of
those tracks sharing the same signals (same genre group, low
plays, unrated, not favorited). No discriminator already in
the dump (year, date added, album) is a tempo or a vibe
signal, so widening the spread on one of those would be
inventing a tempo, not measuring one. The tuning weakness
stays documented as-is; do not claim a fix here.

**Still unproven on a Mac:** the stamp (including whether
`description` is settable on a user playlist), menu runs,
notifications, size-capped shuffle applies, dedupe name lines
in a real run log, and the 48h daily precondition (an evening
probe covering two mornings). The remaining throwaway
checklist items from the stable-prep package are unchanged.

## 2026-10-29 — Stable-preparation package (installer, daily run, migration, functionality audit)

**What this build adds, on branch experimental only:** a macOS
installer (`setup-python.sh`), a daily runner (`daily.sh`), a
migration/rollback script (`migrate-to-python.sh`), a daily
library-manifest writer (`seter_shuffle/manifest.py` plus the
`library-manifest` CLI command), and a full v2.6 functionality
audit (below). No merge to main, no stable release, no tag was
created for this work, and nothing ran on Spencer's Mac.

**Installer usage (from the unzipped build folder, macOS only):**

```bash
bash setup-python.sh                     # install + 8:00 AM daily run
bash setup-python.sh --no-daily          # install only, no schedule
bash setup-python.sh --hour 9            # install + daily run at 9:00 AM
bash setup-python.sh --uninstall         # remove Python schedule + install dir
```

The installer copies local files only (nothing is downloaded),
installs to a NEW directory (`~/Documents/SeTeRShufflePython`),
writes a NEW launchd plist (`com.seter.python.daily`), records
the version marker `3.0-proposed`, is idempotent for the same
version, and REFUSES a different installed version unless
`--force` is given. It never touches the v2.6 install, its
backups, its history, or its `com.seter.daily` job.

**Daily run (proposed: 8:00 AM, matching v2.6):** the time lives
in exactly one place, `DAILY_HOUR`/`DAILY_MINUTE` at the top of
`setup-python.sh`; the plist is generated from those variables.
`daily.sh` saves a once-a-day library manifest (kept 14 days),
dedupes the daily playlist (no-op when clean), shuffles it in
place, then refreshes "SeTeR Rediscover". It NEVER auto-probes
and NEVER borrows another target's mapping: it refuses before
touching Music unless BOTH the daily playlist and "SeTeR
Rediscover" have fresh (<24h) per-target mappings. That is a
known stable gap (see below): a scheduled daily run fails closed
on any day without a manual sortprobe in the previous 24 hours.

**Migration and rollback (explicit only):**

```bash
bash migrate-to-python.sh --dry-run   # default: print the plan, change nothing
bash migrate-to-python.sh --confirm   # disable v2.6 daily job, enable Python job
bash migrate-to-python.sh --rollback  # restore the v2.6 daily job
```

`--confirm` unloads `com.seter.daily` and renames its plist to
`com.seter.daily.plist.disabled-<timestamp>`; it never deletes,
moves, or edits the v2.6 script, backups, apps, or history.
Rediscover history (`~/Documents/SeTeRShuffle/rediscover-history.tsv`)
is read as-is by the Python run, so it carries over with no copy.
Rollback restores the newest disabled v2.6 plist and leaves the
Python install in place.

**Version naming:** the proposed stable name is v3.0 (major
bump: the implementation language changed from AppleScript to
Python, and the mapping model changed to per-target sort-matched
mappings). The installer marks installs `3.0-proposed` to make
clear this is not yet a stable release. No v3.0 tag or release
exists, and none is created until Spencer approves the exact
change list.

**Full functionality audit — v2.6 daily behavior vs Python:**

| v2.6 behavior | Python equivalent | Status |
|---|---|---|
| True-random Fisher-Yates shuffle, artist spacing | `shuffle` core, spacing 2, featuring = same artist | Parity (unit-tested) |
| Rediscover scored picks, preview, 14-day cooldown, max 3/artist, stale 60d, disliked/unchecked/skip-heavy exclusions | `rediscover` / `rediscover-preview`, same settings, history only after successful apply | Parity (unit-tested) |
| Remove duplicates (daily, and menu) | `dedupe`, first-occurrence order, no-op when clean | Parity, except: v2.6 logs each duplicate removed by name; Python logs counts only |
| Undo last shuffle/dedupe | `undo` / `restore` from per-run main backup + `.prev` chain | Parity, stronger backups; extra gate: undo requires a fresh per-target mapping |
| Backup snapshots before any change, restore on failure | Per-run snapshots, installed as main backup only after verified apply | Stronger than v2.6 (v2.6 overwrote one backup file per run) |
| Daily library manifest, kept 14 days | `library-manifest` TSV (persistent_id, artist, album, title), written by `daily.sh`, pruned at 14 days | Parity, new in this build |
| Daily run at 8:00 AM: dedupe + shuffle + Rediscover, no dialogs | `daily.sh` + `com.seter.python.daily` plist at 8:00 AM | Built, UNPROVEN on a Mac; plus the mapping-freshness gap below |
| Flow and flowPreview | `flow` / `flowPreview`, 50 songs, energy arc | New functionality (Flow was experimental, not v2.6 stable); proven once on a Mac for SeTeR Flow (2026-10-29, .5); energy still flat (47-50) for gospel-heavy libraries, a tuning weakness, not a parity gap |
| Interactive menu app and one-click sandwich app | None | GAP, plainly: Python runs from Terminal only; no .app bundles, no menu, no dialogs |
| Playlist description stamp ("Last reshuffled:") | None | GAP: Python does not stamp playlist descriptions |
| macOS notifications/dialogs on success/failure | Logs only (`run.log`, `daily.log`) | GAP by design: logs replace dialogs; no notification is sent |
| Library shuffle with size choice (100/250/500/1000/all into "SeTeR Shuffle") | CLI `--size` exists, but `run.sh shuffle` (no playlist) always uses the whole library | PARTIAL GAP: size choice is CLI-only, not wired into run.sh |
| Daily run with no manual step | None | GAP, the important one: v2.6 daily needed no probe; the Python daily run refuses without fresh (<24h) per-target mappings for both targets, and `daily.sh` never auto-probes. Until that rule changes, a scheduled daily run is not a drop-in replacement for v2.6's daily run |

NOTE: this table is the stable-prep snapshot. The drop-in
entry above it supersedes it: mappings are now 48h, the menu,
stamp, notifications, size wiring, and dedupe name logging are
all built, and only Flow energy tuning (and the no-.app-bundle
fact) remain open.

**Tests here:** full suite re-run after the final code state
(175 tests passed, 0 failed); shell syntax checked
for `setup-python.sh`, `daily.sh`, `migrate-to-python.sh`,
`run.sh`, and `check-python.sh`. New tests
(`tests/test_stable_prep.py`) cover installer idempotency,
version refusal/force, plist generation and hour override,
migration dry-run/confirm/rollback file effects, daily mapping
pre-checks (missing and stale), daily dry-run, and the manifest
writer (columns, rows, CLI).

**Still unproven on a Mac, plainly:** the installer run, the
launchd daily run, migration and rollback, and the remaining
throwaway checklist items (throwaway shuffle+undo, dedupe on a
doubled throwaway, negatives, flow undo). The installer,
daily.sh, and migration script have never executed on a Mac;
their tests here prove shell logic with override directories,
not macOS launchd, osascript, or Music behavior.

## 2026-10-29 — Per-target mapping guard and undo -1728 fallback (.5, focused fix for the two 15:38 PT Flow failures)

**Why, plainly:** after .4 was published, Spencer ran
`./run.sh flow "SeTeR Flow"` twice from the .4 folder, and both
runs failed in two separate places. First, flow compute and
validation passed, then apply failed verification ("final song
order does not match the desired order under mapping
reversed"), apply restored from the per-run snapshot, and then
run.sh's restore via undo failed with the same AppleScript
-1728 bulk-read error ("Can't get persistent ID of every
track of user playlist id 78940 whose media kind = song").
State files on his Mac prove: both SeTeR Flow per-run
snapshots are 0 bytes (the playlist was empty at apply
start), no main SeTeR Flow backup was ever installed, and the
recorded mapping was "reversed", measured on throwaway "My New
Sandwich Recipe" at 13:13 PT.

Failure 1, mapping transfer: the .4 runs used the reversed
mapping measured on the main playlist (sorted Playlist Order
descending) for a NEW target playlist, SeTeR Flow, whose sort
is the default/manual sort. A reversed build on a
forward-sorted playlist lands backwards, so verify correctly
refused. The .4 create-then-read fix worked for the snapshot
(the empty fallback let the snapshot step succeed); this
failure is the mapping being applied to a target with a
different sort. It is not a -1728 failure and not a snapshot
failure.

Failure 2, undo -1728: the .4 empty fallback went into
apply-order and the retired probe script, but NOT into
undo.applescript (and restore-original was the same). Undo's
first step is a bulk playlistIDs read on the target, which
fails with -1728 on the empty SeTeR Flow playlist, so undo
died before changing anything, and run.sh reported it as
"playlist may be partial" when nothing had changed.

**What changed:**

- `run.sh`: mappings are now PER-TARGET. `mapping_file_for`
  builds a mapping filename from the target name plus a hash,
  the same scheme as backups. `mapping_for_build` takes a
  target argument and reads ONLY that target's file; it
  validates the file's TARGET field matches, requires a
  non-empty SORT field, and requires a fresh (<24h)
  timestamp. The pre-.5 shared `sort-mapping.txt` is IGNORED:
  if only it exists, the build refuses with a message saying
  so. `mapping_info_for` logs the mapping, throwaway, sort
  label, and target (via log(), never captured) so the
  provenance is visible in GATE lines before any build.
  `sortprobe` now requires three arguments:
  `./run.sh sortprobe <throwaway> <target> <sort-label>`,
  and records MAPPING, THROWAWAY, TARGET, SORT, and TIMESTAMP
  in the per-target file; a failed probe deletes ONLY that
  target's file. Undo, restore, and apply_order call sites
  pass the target and print the provenance. The post-apply
  restore branch greps the log from the restore STEP line for
  the PLAYLIST_UNTOUCHED marker and logs "untouched, NOT
  partial" in that case, keeping the CRITICAL "may be
  partial" message for all other restore failures.
- `bridge/undo.applescript` and
  `bridge/restore-original.applescript`: `playlistIDs` now
  has the .4-style empty fallback (bulk-read error plus an
  unfiltered track count of 0 returns {}, anything else
  rethrows), `deletePlaylistSongs` falls back to the
  unfiltered count the same way, and the pre-change snapshot
  read/write is wrapped so a failure there rethrows with a
  PLAYLIST_UNTOUCHED marker ("playlist untouched").
  `bridge/sort-probe.applescript` got the same fallback pair.
  `bridge/diagnose-playlist.applescript` (read-only) now
  guards its bulk song-ID read the same way: count 0 reports
  empty, anything else errors as unreadable rather than
  guessing. Audit of every `playlistIDs` handler: apply-order,
  undo, restore-original, sort-probe, and the retired
  probe-order all now carry an empty fallback. The one
  deliberate exception is `bridge/dump-library.applescript`,
  which has no playlistIDs handler and whose bulk filtered
  reads on the library (940 songs, proven working) were left
  alone; a dump of an empty playlist could theoretically hit
  the same -1728, but it fails before any change and is not
  a build path that modifies anything.
- `tests/test_per_target_mapping.py` (new, 20 tests):
  behavioral bash-extraction tests for mapping_for_build
  (valid per-target capture exactly; missing file refuses;
  legacy shared file ignored with an "ignored" stderr
  message; TARGET-field mismatch refuses; missing SORT
  refuses; stale timestamp refuses; different targets get
  different mapping files; mapping_info_for prints
  target/throwaway/sort/mapping) and structural tests
  (sortprobe requires target + sort label and records
  TARGET/SORT lines; sortprobe failure deletes only the
  per-target file; build callers pass target and print
  provenance; mapping_for_build never reads the legacy
  file's MAPPING; restore path distinguishes untouched from
  partial; undo/restore/sort-probe playlistIDs + delete
  fallbacks present; undo/restore PLAYLIST_UNTOUCHED markers
  present; every playlistIDs handler across apply-order,
  undo, restore-original, sort-probe, and probe-order has an
  empty fallback). Two older test files were updated for the
  API change, not weakened: test_mapping_stderr.py now
  extracts mapping_file_for, writes fixtures to the
  per-target file, and passes a target; the sortprobe
  failure and restore assertions in
  test_delete_empty_and_dedupe.py now name the per-target
  file and the target-argument call.
- `BRIDGE-SAFETY.md`: new failure modes 35 (mapping
  transfer) and 36 (undo -1728), failure-mode table rows,
  and procedure updates: a mapping measured on one
  playlist's sort NEVER transfers to a playlist with a
  different sort, with Flow as the worked example (main
  descending reversed vs new SeTeR Flow default forward).
- `STABLE-PROMOTION-TESTS.md`: Flow now needs its OWN
  sortprobe on a throwaway matching SeTeR Flow's sort
  (new step 10c and record row); a build for any other
  target must refuse without its own per-target mapping.
- `README-PYTHON.md`: per-target mapping, new sortprobe
  usage, and the .5 test count.

**Still unproven on a Mac:** everything in .5, like every
bridge change before it. In particular the mapping-transfer
fix cannot be proven without a Mac run on a new-sort target:
a Flow build must refuse under the main playlist's reversed
mapping (or rather, must refuse for lack of a SeTeR Flow
mapping) and must succeed only after its own sortprobe on a
throwaway set to SeTeR Flow's sort. The undo -1728 fallback
likewise needs a Mac run against an empty playlist. Full
suite here: 161 tests passed (141 existing + 20 new).

## 2026-10-29 — Create-then-read fix for flow into a missing playlist (.4, small focused release on the road to stable)

**Why:** after .3 was published, Spencer ran `./run.sh flow
"SeTeR Flow"` and the apply failed with AppleScript error
-1728 at the first bulk ID read, before any snapshot existed.
Safety held (nothing changed, no snapshot written), but the
cause is now diagnosed, not guessed: Spencer confirmed the
target playlist did not exist yet in Music. So the failing
path is `resolvePlaylist(allowCreate=true)` creating the
playlist via `make new user playlist`, followed by a bulk
filtered read on the freshly created empty playlist. Whether
the make-new reference went stale under Music / iCloud sync
or the filtered bulk read itself fails on a brand-new empty
playlist cannot be distinguished from the Mac evidence, and
the fix covers both rather than depending on either one.

**What changed:**

- `bridge/apply-order.applescript`: after creating a
  playlist, the script re-resolves it by id with a fresh
  lookup (`first user playlist whose id is newID`) and
  builds only from that reference; a failed fresh lookup
  aborts before anything changes. `playlistIDs` falls back
  on a bulk-read error to an unfiltered track count: count
  0 proves the snapshot is empty and returns {}, anything
  else rethrows, because a snapshot for a non-empty
  playlist must never be guessed. `deletePlaylistSongs`
  applies the same fallback to its empty re-read, so a
  fresh empty playlist passes the delete-empty gate it
  already satisfies; a filtered error with tracks present
  still fails, since song vs non-song entries cannot be
  told apart in that case. The snapshot comment in `run`
  now states that a created playlist's snapshot is
  legitimately empty, and nothing is duplicated until the
  delete-empty verification passes.
- `bridge/probe-order.applescript` (retired from builds,
  standalone sanity check only): its `playlistIDs` carries
  the same empty fallback for consistency. Audit result:
  no build-path script besides apply-order creates a
  playlist; undo, restore-original, and sort-probe resolve
  existing playlists and refuse when missing.
- `tests/test_create_then_read.py` (new, 7 tests):
  structural tests on the AppleScript text: only
  apply-order (build path) and the retired probe-order
  create playlists; the create branch re-resolves by id
  after the make-new; the empty fallback and the
  delete-empty fallback are present; snapshot precedes any
  build in `run`; nothing duplicates before the
  delete-empty gate.
- `BRIDGE-SAFETY.md`: new failure mode 34 with the
  diagnosis, the fix, and the Mac test (flow into a
  missing playlist must create and apply exactly, then
  flow again on the existing playlist must refresh it);
  failure-mode table row 33 added; test count updated to
  141.
- `STABLE-PROMOTION-TESTS.md`: Step 10 gains the
  missing-playlist flow test (delete "SeTeR Flow", flow
  must create + APPLY OK with no -1728, flow again must
  refresh), plus record row 10b.
- `README-PYTHON.md`: test count updated to 141.

NOT PUBLISHED YET: this tree is unreviewed by the parent
and unproven on a Mac; the -1728 fix itself has never run
against Music, and the Mac test in mode 34 is still owed.
Nothing here has been pushed by this build (the parent
creates the release).

## 2026-10-29 — Visible mapping-gate errors, plus the stable-promotion test checklist (.3, small focused release on the road to stable)

**Why:** after .2 was published, Spencer ran a shuffle that stopped
after "compute shuffle order" with no visible error. Cause: in .2,
a missing or stale sort mapping makes `mapping_for_build` fail, but
that failure went through `logfile()` only, so it reached the run
log file and never reached the terminal. The .1 bug was the mirror
image (log() teeing to stdout polluted the captured mapping). .3
fixes the reporting without reintroducing .1: failures in
`mapping_for_build` go through a new `logerr()` helper (log file
AND stderr, never stdout, since stderr is never captured by
$(...)). The same audit found one more function with the same
shape: `probe_mode` (also called inside $(...)) hid its failure
the same way, so its failure branch uses `logerr()` too.
`check-python.sh` was audited and already routes its errors to
stderr; `backup_path_for` emits only a path and has no logging
to pollute anything. NOT PUBLISHED YET: this tree is unreviewed
by the parent and unproven on a Mac; nothing here has been
pushed by this build (the parent creates the release).

**What changed:**

- `run.sh`: new `logerr()` helper; all four `mapping_for_build`
  failure branches (no mapping file, non-forward/reversed mapping,
  bad timestamp, mapping older than 24h) and the `probe_mode`
  failure branch now use it. Success info in both functions stays
  logfile-only (it is not an error, and terminal noise there
  buys nothing). Comments in both functions now state the .3
  rule explicitly so the next edit does not regress it either way.
- `tests/test_mapping_stderr.py` (new, 6 tests): executes the
  real `mapping_for_build` extracted from `run.sh` under bash for
  all four failure cases (exit non-zero, GATE FAILED on stderr,
  stdout empty) and for a valid mapping (captures to exactly the
  mapping word, stderr empty), plus structural guards (no `log()`
  call inside `mapping_for_build` or `probe_mode`, failure
  branches use `logerr()`, `logerr()` routes to stderr and the
  log file).
- `STABLE-PROMOTION-TESTS.md` (new): the Mac checklist Spencer
  runs himself, in order, with exact commands and pass criteria:
  Stage 0 sortprobe on a descending throwaway; Stage 1 sort
  controls (descending, ascending, manual shuffle + undo exact
  both ways; title-sorted throwaway aborts untouched and the
  follow-up build refuses with a VISIBLE terminal error, the new
  .3 behavior tested explicitly); Stage 2 dedupe on a doubled
  throwaway, dedupe no-op on a clean throwaway, failed-apply
  backup intactness, the negative suite, flowPreview/flow/undo,
  rediscover-preview, restore from a backup file; Stage 3 real
  playlist only with explicit approval, starting with a
  backup-order restore check, not a shuffle. It also lists the
  stable-promotion gaps this release does NOT resolve: no
  installer, no launchd schedule, undecided version naming, and
  undesigned migration from the v2.6 AppleScript daily run, with
  stable v2.6 left intact as fallback.

**Still unproven on a Mac (unchanged from .2, plus .3 itself):**
every AppleScript change, the delete-lag mechanism itself, the
sort-matched mapping end to end on throwaways, the per-run backup
chain under a real failing apply, and now the .3 stderr routing
on a real terminal (proven here under bash, not in Terminal).
The one Mac success that does exist is the 2026-10-29 12:44 PT
real-playlist shuffle under .2 (sortprobe measured reversed,
806 songs applied in exact order, APPLY OK); it does not replace
the throwaway checklist above.

## 2026-10-29 — Delete-empty verification, dedupe, and a full runner sweep (sixth Python change, after a third real failure)

**Why:** on 2026-10-29 at 00:41 PT Spencer ran the OLD .5 code
again (a second download folder, not the sort-aware .1 build) on
the real playlist, and the dump counted 1612 songs: the playlist
had doubled between the 00:21 diagnostic (806 songs) and the
00:41 run to exactly two copies of each song, backup =
reverse(original) twice, pre-undo snapshot = original twice. The
.5 apply and undo then failed verification in the same loop. The
`.prev` backup (13701 bytes) still equals the original 806-song
order, and Spencer says he has his own backup playlist, so
recovery is not urgent — but the script must be fixed, and this
build also sweeps every other open issue in BRIDGE-SAFETY.md and
INVESTIGATION-2026-10-28.md instead of only the two named items.
Published as exp-2026-10-29.2 (prerelease, asset verified live).
Unproven on a Mac at publish time; nothing in this entry was
pushed by the build itself (the parent created the release).

**What changed (all in `seter-shuffle-python/`, nothing else):**

- Delete-empty verification, in apply-order, undo,
  restore-original, and sort-probe (new `deletePlaylistSongs`
  handler in each): delete, re-read, confirm 0 song entries,
  retry up to 5 times with a 5-second settle delay; if entries
  remain, return the `delete-not-empty` sentinel and duplicate
  NOTHING. Callers restore from the verified backup (apply) or
  the pre-undo snapshot (undo) only if the playlist was actually
  changed (a partial delete), and report "playlist unchanged" if
  it still matches the backup/snapshot exactly. The doubling
  mechanism itself (delete lagging at 806-song scale) is
  UNPROVEN: the guard does not depend on it, and if no throwaway
  reproduces the lag, the guard stands as prevention, not as a
  proven root cause. Bulk reads (`playlistIDs`, `librarySize`)
  are now inside 3600-second timeout blocks like the build loops.
- Dedupe command: `./run.sh dedupe <playlist>` dumps one
  playlist, computes unique songs in first-occurrence order
  (`seter_shuffle/order_direction.py::dedupe_ids`, plus the CLI
  `dedupe` command), validates it with a new `dedupe` mode
  (exactly the dump's unique set, each ID once; a repeat, a drop,
  or an invented ID refuses), then applies it through the SAME
  safe rebuild path (snapshot backup, delete-empty verification,
  sort-aware duplicate, exact verify, restore on failure).
  Dedupe forces the bridge duplicate allowance to "0" (its order
  is unique by construction). If the playlist holds no
  duplicates, run.sh applies NOTHING (no rebuild of a clean
  playlist). Documented everywhere it matters: dedupe preserves
  first-occurrence order in the current list-read order, NOT the
  original backup order, so on a reversed doubled playlist it
  yields unique songs in reversed order and a backup-order
  restore is still a separate step afterwards.
- Runner bug fix, found by code review (BRIDGE-SAFETY.md mode
  31): the .1 runner's `mapping_for_build` logged with `log()`
  (tee to stdout) while every caller captures it with `$(...)`,
  so every captured mapping carried a log line and the bridge
  refused it. **No .1 build through run.sh could have run at
  all** (direct osascript calls with a clean mapping word would
  have worked, but run.sh is the documented path). Fixed by
  logging with `logfile()` only inside `mapping_for_build`, and
  guarded by a structural test that extracts the function body
  and refuses any `log ` call in it. The fix was verified by
  extracting the .2 function verbatim and capturing it to
  exactly `[reversed]` (the .1 function captured to a polluted
  two-line string in the same harness).
- Backup chain (BRIDGE-SAFETY.md mode 32): the 00:41 run
  overwrote the main backup with the doubled state, and only
  `.prev` saved the original; one more failed run would have
  overwritten `.prev` too. `apply_order` now writes the
  pre-change snapshot to a fresh per-run file
  (`<backup>.run-<timestamp>-<pid>.txt`), installs it as the
  main backup ONLY after a verified successful apply (previous
  main backup preserved as `.prev`), and keeps the newest 10
  per-run snapshots. On apply failure the restore attempt uses
  the per-run snapshot and the log states the main backup was
  NOT overwritten. Undo never writes to the main backup path.
- Stale-mapping and restore gaps (mode 33): a sort-probe failure
  now DELETES the recorded mapping file (and writes it atomically
  on success), so a failed re-probe cannot leave an old mapping
  in place for a build under an unknown sort. New
  `./run.sh restore <playlist> <backup-txt>` gives
  restore-original the same freshness-checked gate as undo;
  direct osascript calls remain possible and remain ungated on
  freshness by construction, and the docs now say so plainly:
  use run.sh, never call a bridge script directly for a build.
  `run.sh undo` refuses before anything is deleted when the main
  backup file is missing, listing recent backups instead.
- Sort-probe "other" aborts now report the throwaway's state in
  words (restored to snapshot vs left holding the rotation
  order), not just a boolean, and run.sh's sort-probe failure
  path names the throwaway snapshot file to check.
- Undo, apply, and restore parity, checked by re-reading all
  three: every run.sh path reads the recorded mapping fresh
  (<24h), forward/reversed only, passes it identically, and the
  bridge scripts each refuse any other mapping string before
  resolving anything. No run.sh path builds without a mapping,
  and no bridge script builds with an "other" mapping. The one
  remaining bypass is direct osascript invocation (freshness
  only, not mapping presence), documented as expert-only above.
- Mac procedure updates (BRIDGE-SAFETY.md Stage 2): dedupe on a
  doubled throwaway, dedupe again on the clean throwaway (must
  apply nothing), a failing apply must leave the main backup
  byte-identical, and a failed sort-probe must make the next
  build refuse for lack of a mapping.
- Tests: 128 passed, 0 failed here (101 previous + 27 new in
  `tests/test_delete_empty_and_dedupe.py`: dedupe order
  computation including the reversed-doubled shape, dedupe
  validation file and in-memory, CLI dedupe on dump files
  including the empty-playlist nonzero exit, and structural
  guards for the delete-empty handler in all four scripts, the
  logfile-only mapping reader, the per-run backup chain, the
  sort-probe mapping deletion, and the restore command). Shell
  syntax of run.sh checked with `bash -n`.

**Still unproven on a Mac (honest list, with the test that would
prove each):** every AppleScript change above, as before; the
delete-lag mechanism itself (a throwaway whose delete can be
shown to lag, or a doubled throwaway deduped cleanly, proves the
guard, not the mechanism); the sort-matched mapping end to end
(sortprobe on a descending throwaway, then descending/ascending/
title controls, then negatives, then dedupe on a doubled
throwaway, real playlist only at Stage 3 with Spencer's explicit
approval); the per-run backup chain under a real failing apply;
the size-ladder and selection-context and duplicate-copy tests
from INVESTIGATION-2026-10-28.md step 5, which no throwaway run
has yet performed and which could still implicate a property
beyond sort; and whether the current doubled real playlist's
state matches the last snapshots (a fresh read-only diagnostic
is still owed before any real-playlist step). Nothing here
claims any of that is proven.

## 2026-10-29 — Sort-matched build mapping replaces the fresh probe (fifth Python change, after a second real failure)

**Why:** on 2026-10-28 at 23:46 PT the .5 bridge was run on the
real playlist "My New Sandwich Recipe" (806 songs) again, skipping
the throwaway stages. Its fresh 3-song probe reported "forward" on
all channels, yet apply failed verification and restore failed,
and undo failed the same way, exactly as in .4. The backup taken
at the start of the .5 run equals the original backup exactly, and
the pre-undo snapshot is again the EXACT REVERSE of the original
backup, 806/806, same set. No song left the library. The user
then confirmed the missing property: the real playlist is sorted
in Music by playlist order DESCENDING, which no fresh probe
playlist shares. A read-only diagnostic on 2026-10-29 then killed
the draft sort design (classify by comparing the every-track list
against the track-index order): the current list read is the exact
reverse of the original backup by its ends, positional first/last
agree with the list, and the list's first track carries index 1,
which no "list is reverse of manual index order" story predicts.
So index is not a manual-order reference on this Music version,
and both the fresh probe and any index classification are dead.
NOT PUBLISHED: this tree is unreviewed by the parent and unproven
on a Mac; nothing here has been pushed.

**What changed (all in `seter-shuffle-python/`, nothing else):**

- New `bridge/sort-probe.applescript`: the only direction
  authority for builds. It takes a throwaway the user has set to
  the target's sort, snapshots it atomically, builds a rotation
  of its order (items 2..n plus item 1; for 5+ distinct songs
  neither the snapshot order nor its reverse), reads it back,
  and classifies the end-to-end mapping: "forward" (read ==
  build), "reversed" (read == exact reverse of build), or
  "other" (anything else: another column sort, a partial build,
  or unpredictable behaviour). It then restores the throwaway
  under the measured mapping and verifies that restore; a failed
  restore is a hard error naming the snapshot file. It requires
  at least 5 distinct song IDs, refuses ambiguous names and
  non-user playlists, and never touches any other playlist.
- `run.sh`: new `./run.sh sortprobe <throwaway>` command that
  runs the sort-probe, parses its `MAPPING:` line, and records
  the mapping with the throwaway name and a timestamp in the
  state dir (valid 24 hours). Apply and undo now read that
  recorded mapping and refuse without a fresh one; they pass the
  mapping (not a probe mode) to the bridge scripts. The old
  `probe` / `probe-keep` commands stay as standalone sanity
  checks only and are consulted by no build.
- `bridge/apply-order.applescript`, `bridge/undo.applescript`,
  and `bridge/restore-original.applescript`: all converted to
  mapping-only. The mapping argument is required (old probe-mode
  strings fail loudly). Build/verify formulas: to land list-read
  order D, duplicate D under "forward" and reverse(D) under
  "reversed"; verification always compares the list read
  against D. Restore uses the same formulas with D = the backup
  order. An "other" mapping refuses before any change. There is
  no flip on a failed verify anywhere: restore from backup and
  exit non-zero. The retired 2026-10-28 one-off fix script on
  the user's Mac (`~/Downloads/seter-fix-playlist.applescript`)
  must still never be run; the rewritten tree file is a
  different, mapping-based script and is itself unproven.
- `bridge/diagnose-playlist.applescript`: header only. It now
  states explicitly that track index is NOT a manual-order
  reference and must never be used as a classification input.
  Its printed lines are unchanged.
- `bridge/probe-order.applescript`: header only. It is now
  marked retired from builds; no build may wire it back in.
- `seter_shuffle/order_direction.py`: legacy probe-mode
  functions kept and marked legacy; the mapping section
  (`parse_mapping`, `mapping_from_build_result`,
  `build_for_mapping`, `expected_for_mapping`) is the single
  source of truth for the formulas, mirrored by the AppleScript
  handlers `buildForMapping` / `verifyAgainst`. The
  Python sort-classification functions from the discarded first
  design were removed, and their test file deleted.
- `tests/test_sort_mapping.py`: 14 tests covering mapping
  classification (including the rotate probe-order unambiguity
  point), the forward/reversed build formulas, the
  verify-expectation-is-desired invariant, a reversed round-trip,
  and the restore formula with the real backup ends (first
  `B49A108A0E5553DB`, last `54BC5E32EB0D0F8E`).
- `BRIDGE-SAFETY.md`: new failure mode 30 at the top (sort
  mechanism, exact-reverse evidence, why the .5 probe missed it,
  why index classification was discarded, the abort behaviour,
  and the falsifiers), audit item A1 updated to the confirmed
  model, the .5 probe section marked superseded, and the Mac
  procedure rewritten: Stage 0 is now the read-only diagnostic
  plus a full-dump comparison, the UI sort check, the
  sort-matched sort-probe gate, and the throwaway sort controls
  (descending must fail on old code and pass on new code,
  ascending/manual must pass, title-sorted must abort
  untouched); Stage 3 is a real playlist only with explicit
  user approval after seeing Stage 0-2, plus a display eyeball
  after any restore. Nothing touches "My New Sandwich Recipe"
  before Stage 3.
- `README-PYTHON.md`: bridge description and suggested Mac
  verification order rewritten around sort-probe and the
  mapping gate.

**Still unproven on a Mac:** every AppleScript change above.
The Mac procedure in BRIDGE-SAFETY.md is the proof plan, in
order, throwaways first. The restore goal the bridge can
measure is list-read order == backup order; whether the
display follows it is a Stage 3 eyeball check, not something
any script proves.

## 2026-10-28 — Probe-driven order direction (fourth Python change, after a real failure)

**Why:** on 2026-10-28 the .4 bridge was run straight on a real
playlist, "My New Sandwich Recipe" (806 songs), skipping the
throwaway stage. Apply, its restore, and undo all failed exact-order
verification in a loop. No song left the library. The two backup files
pulled off that Mac prove the inside of the loop: the pre-undo
snapshot is the EXACT REVERSE of the original backup (806/806 same
unique IDs, reversed; re-verified from the files, not taken on
faith). Either duplicating inserts at the top of a playlist, or the
every-track read returns tracks reversed; the backup files alone
cannot tell which. The user later said the playlist "looks normal",
which is consistent with both mechanisms ending back at the original
display after the full chain, and proves nothing about exact order
for 806 songs. This change replaces guessing with a probe. NOT
PUBLISHED YET: this tree is unreviewed by the parent and unproven
on a Mac; nothing here has been pushed.

**What changed (all in `seter-shuffle-python/`, nothing else):**

- New `bridge/probe-order.applescript`: creates a 3-song probe
  playlist, duplicates in a known order, and reads it back by the
  every-track list, by each entry's `index` property (sorted
  ascending), and by positional first/last tracks. Verdict is
  "forward", "insert-reversed", or "read-reversed" only when the
  channels agree on one model; anything else is "ambiguous". The
  probe deletes its own playlist (and on error paths too) unless
  run with "keep" for the manual eyeball check. The positional read
  travels through the same scripting bridge as the list read, so it
  is a contradiction check only, never the sole basis for a
  direction; the manual eyeball step in BRIDGE-SAFETY.md is the only
  truly independent read. If the `index` property is unavailable,
  the probe reports ambiguous (fail-closed), never a guessed mode.
- New `seter_shuffle/order_direction.py`: the testable mirror of the
  bridge's mode formulas. An apply build wants a display order O
  (duplicate O, except insert-reversed duplicates reverse(O);
  verify against O, except read-reversed verifies against
  reverse(O)). Every restore build wants to return to a list-read
  snapshot T (duplicate T under "forward", reverse(T) under either
  reversed mode; verify against T in all modes). Apply, undo, and
  restore-original carry handlers with the same names and the same
  formulas; if they ever drift from this module, the bridge is
  wrong even though the Python tests pass.
- `bridge/apply-order.applescript` and `bridge/undo.applescript`
  rewritten around the mode: the mode argument is REQUIRED (an old
  unprobed call fails loudly before anything changes); every build,
  verify, and restore uses the mode formulas; there is NO
  flip-on-failure fallback in either script. Build and restore loops
  run inside `with timeout of 3600 seconds` blocks (the .4 build
  took ~2 minutes for 806 songs). Apply's argument order changed:
  mode, then duplicate flag, then optional whole-library song count
  (run.sh no longer passes a playlist dump's count as a library
  count; see below).
- `bridge/restore-original.applescript` rewritten: its default path
  now probes (mode "auto") or takes an explicit probed mode, and
  builds/verifies with the mode formulas. The old flip logic
  survives ONLY as explicit "flip" mode, documented as
  throwaway-only, because under read-reversed it rebuilds an
  already-correct playlist in reverse order and calls that a
  success. Never run the 2026-10-28 version of that script again,
  and never run "flip" on a real playlist.
- `run.sh` probes before every apply and undo (probe_mode, fresh
  timestamped probe playlist per run); an ambiguous or failed probe
  aborts with the real playlist untouched. New `./run.sh probe`
  (measure and report) and `./run.sh probe-keep` (leave the probe
  playlist for the eyeball check, then delete it by hand). Undo and
  apply-failure restores pass the same probed mode to undo.
  Backup filenames now also neutralize newlines/carriage returns.
  One-playlist shuffles pass --allow-duplicates to the CLI and the
  duplicate allowance flag to apply (see below); whole-library
  dumps pass the library count as before.
- Duplicate-entry playlist shuffles now work instead of failing
  closed (audit item A14): load_library gains allow_duplicates
  (CLI --allow-duplicates, passed by run.sh only for one-playlist
  shuffles); validate-order's shuffle check is now multiset
  equality and its duplicate rule is "no more copies than the
  dump"; apply-order's duplicate check is skipped only under the
  allowance flag. Whole-library orders still refuse any repeat.
- `bridge/dump-library.applescript`: jsonEscape rewritten as a
  character loop that escapes every control character as \u00XX
  (audit item A16); the old version left non-standard control
  characters raw, which made the JSON unparseable and stopped the
  run fail-closed.
- `BRIDGE-SAFETY.md`: failure mode 29 (the reversal, with the
  evidence and both mechanisms), the probe and its honest limits,
  a full further-audit table (A1-A20: UI sort settings, iCloud
  sync, now-playing track, cloud-only tracks, ID changes, non-song
  entries, timeouts, mid-run duplicate names, the .4 library-count
  argument bug, backup filename characters, stale dumps, order
  JSON/text gaps, dump order vs display order, the .4 duplicate
  refusal, .4 hardening re-check, dump escaping, CLI --size,
  validate-backup inconsistency, the old flip script, probe
  parsing), and a rewritten Mac procedure starting with Stage 0
  (probe, then eyeball the kept probe playlist) and forbidding any
  real playlist before Stage 3.
- Tests: 86 passed, 0 failed here (67 previous + 19 new in
  tests/test_probe_mode.py: mode formulas in all modes including
  empty/single/duplicate inputs and input immutability, multiset
  shuffle validation, load_library duplicate modes, CLI playlist
  shuffle with and without --allow-duplicates, probe verdict
  parsing, and structural presence checks for the probe script and
  mode handlers). Shell syntax of run.sh and check-python.sh
  checked with `bash -n`.

**What the Mac run must prove now (bridge constructs, all unverified):**

- The probe itself, first: `./run.sh probe` reports one of the three
  modes with PROBE_CLEANUP_OK, and `./run.sh probe-keep`'s on-screen
  probe playlist order in Music matches that verdict. If the verdict
  is ambiguous, or the eyeball disagrees with it, STOP and report
  both: no build should proceed on that verdict.
- Whether the track `index` property is exposed on playlist tracks
  in this Music version (if not, every probe is ambiguous by design).
- Then the full throwaway procedure in BRIDGE-SAFETY.md (Stage 1
  happy path including a duplicate-entry playlist, Stage 2 negative
  tests, Stage 3 a real playlist you can afford to have rewritten,
  Stage 4 the force-quit case on a throwaway only). Nothing in this
  build has run on a Mac, including the probe, the mode formulas in
  AppleScript, the new jsonEscape loop, and the timeout wrappers.

**Known limits (honest list):**

- The bridge cannot be executed here (no osascript, no Music), so
  nothing in `bridge/` has run at all. Treat it as reviewed, not tested.
- The probe's positional read is not independent of its list read
  (same scripting bridge); the manual eyeball step is the only
  truly independent check, and it is required, not optional.
- Direct apply/undo calls without a mode argument now fail loudly
  by design; only run.sh (or an explicit probed mode) can drive them.
- The old one-off fix script's flip behaviour is preserved only
  behind explicit "flip" mode for throwaways; the 2026-10-28 version
  must not be run again.

## 2026-10-28 — AppleScript bridge hardening (third Python change)

**Why:** Spencer asked for the bridge to be made extremely
bulletproof: no way for songs to be deleted or duplicated, make it
perfect, take your time. This change is the bridge only; the core
ordering logic is untouched.

**What changed (all in `seter-shuffle-python/`, nothing else):**

- New `seter_shuffle/validate.py` plus `validate-order` and
  `validate-backup` CLI commands: the same refuse rules as the
  bridge, applied in Python before osascript ever runs. Empty
  orders, duplicate IDs, IDs missing from the dump, shuffle orders
  that are not exactly the dump's song set, truncated orders (the
  text file must agree exactly with the order JSON, including its
  count), malformed/non-UTF-8 files, and expected-count mismatches
  are all refused with the problem listed. Backups are validated
  too, with duplicates allowed and an empty backup valid (it
  snapshots an empty playlist).
- `bridge/apply-order.applescript` rewritten with a safety header:
  target resolved by filtered lookup (0 = create, >1 = refuse as
  ambiguous, 1 = use that object); `assertUserPlaylist` refuses the
  Library, smart playlists, and anything that is not a regular user
  playlist, failing closed if any check cannot be performed; order
  validated before any change (strict read, empty refusal,
  duplicate check via `sort | uniq -d`); backup written atomically
  (temp file, `mv -f`, re-read and compared exactly) before any
  delete, never truncated in place; build collects lookup failures
  instead of silently skipping; any build, verify, or library-shrink
  failure restores from backup and exits non-zero; verify-after is
  an exact ID-list comparison, not a count check; verification
  itself is wrapped so Music quitting during verify also restores;
  the restore handler never throws from its own verify step.
- `bridge/undo.applescript` rewritten with a safety header: backup
  validated before anything is deleted; target resolved by filtered
  lookup and never created; current playlist snapshotted first to
  `<backup>.pre-undo` (atomically written and verified) so a failed
  undo is recoverable; rebuild collects failures; any rebuild,
  missing-song, or verification failure restores the pre-undo
  snapshot and exits non-zero; empty backup restores an empty
  playlist; backup duplicates reproduced exactly; non-song entries
  never deleted.
- `bridge/dump-library.applescript` hardened: filtered playlist
  resolution (ambiguous names refused); required lists must all
  have exactly n entries or the dump aborts unwritten, so a mid-read
  library change cannot misalign values onto the wrong tracks;
  the bulk-read helper no longer pads to full length (that bug had
  made its count check dead code and blocked the `favorited` to
  `loved` fallback, which now actually runs); output written
  atomically (temp file, `mv -f`, non-empty check), so a failed
  write never leaves a half-written dump.
- `run.sh` rewired: a `step()` helper logs GATE OK / GATE FAILED
  for every step and sends both stdout and stderr to the log, so
  the log proves which gate fired; `validate-order` runs after the
  core computes an order and before any apply; the dump's song
  count is passed to apply as its library-shrink argument; any
  previous backup is preserved as `<backup>.prev` and the backup
  path cleared before an apply, so a stale backup can never be
  mistaken for a fresh one; on apply failure with a fresh backup,
  the runner attempts a restore via undo before exiting non-zero,
  and with no fresh backup it logs that the playlist was not
  changed; history is still recorded only after a successful apply.
  Backup filenames now include a hash of the playlist name, so two
  names differing only by spaces and slashes no longer share a
  backup file (old backup files remain usable by direct osascript
  call).
- `check-python.sh` now refuses loudly if the interpreter path
  contains a space, since run.sh splits its output on the first
  space.
- New `BRIDGE-SAFETY.md`: the full failure-mode table (mode, old
  behaviour, new guard, how to test it on a Mac), the uncovered
  case and its recovery, and the exact Mac verification procedure
  (throwaway playlist first, then a real one, then undo, checking
  counts and exact order at each step).

**What was actually tested here (Linux VM, Python 3.12.3):**

```bash
python3 -m unittest discover -s tests
# Ran 67 tests in 0.577s — OK
bash -n run.sh check-python.sh && echo shell-ok
# shell-ok
```

67 passed, 0 failed (41 pre-existing, all still passing, plus 26
new in `tests/test_bridge_safety.py` covering every validation
rule: empty, duplicate, missing ID, shuffle count/set mismatch,
blank middle line, whitespace ID, order-JSON disagreement
including a truncated text file, expected-count mismatch, flow and
rediscover ineligible IDs, non-UTF-8 and malformed files, backup
missing/corrupt/empty/duplicates, and both CLI commands' return
codes).

**What was NOT tested here, and is not claimed:** every Music
interaction in the bridge scripts. This machine has no Music app
and no osascript, so no bridge script has been executed. Proof
here is line-by-line review (including a grep confirming the only
Music deletes target asserted user playlists, never
`library playlist 1`) plus the Python tests above. The Mac
verification procedure in `BRIDGE-SAFETY.md` is still required,
and no bridge script should be called proven until it has been
run. The one case AppleScript cannot fully cover is also stated
without softening in that document: power loss or force-quit
mid-write cannot run a restore; recovery is re-running undo from
the verified backup file in the state directory.

**Not published:** nothing in this change has been pushed or
released. That decision is for the parent agent.

## 2026-10-28 — Missing-BPM fallback and tag audit (second Python change)

**Why:** Spencer ran `./run.sh flowPreview` on his Mac on 2026-10-28:
940 songs dumped, 938 eligible, 50-song preview, nothing changed,
but almost every energy was exactly 50 (one at 55). The old model
defaulted missing BPM to 50 and his gospel/Christian genres matched
no genre group, so the walk had nothing to climb with.

**What changed (all in `seter-shuffle-python/`, nothing else):**

- New `audit` command (`python3 -m seter_shuffle.cli audit --library
  dump.json`, and `./run.sh audit` on a Mac): counts and percentages
  for BPM present vs missing vs zero, genre present vs missing, the
  most common raw genre strings with counts, played-count bands,
  rating bands, favorited, disliked, enabled, Flow eligibility, and
  the Flow energy spread. It changes nothing in Music. It is the
  diagnostic that separates "library truly lacks BPM" from "dump
  script fails to read BPM": some BPM present means the dump works
  (a dump bug loses BPM for the whole list at once, via the bulk-read
  fallback); zero BPM present means suspect the dump first.
- Missing-BPM energy fallback, with BPM-present songs scoring
  exactly as before (same BPM bands, same legacy genre nudges, same
  single >=20 plays step, same rating/favorited): base 50, expanded
  genre map (gospel/christian/worship/praise -2, latin/reggaeton +6,
  afrobeats/reggae +4, soundtrack -3, old groups unchanged), tiered
  plays (1-4 +2, 5-19 +4, 20-49 +6, 50+ +9), rating (3 stars +2,
  4-5 stars +5, 1-2 stars -10), favorited +5, and a -5 skip penalty
  only when at least 3 plays+skips exist and more than half were
  skips. Skip-heavy songs stay Flow-eligible; the penalty is a
  score, not an exclusion. Clamp stays 5..100.
- Tie-breaking in the greedy walk: on an exact cost tie, prefer a
  genre group different from the previous pick, then higher
  familiarity (plays capped at 100, +25 favorited, +rating stars),
  then the earliest pool song. Deterministic; flat-energy pools no
  longer come out in raw library order.
- `run.sh` gains `./run.sh audit` (dump, then audit, no apply, no
  history write). `README-PYTHON.md` gains the audit commands, a
  section explaining why BPM is not attached to every song, and the
  fallback model in plain words.

**Answer to the question behind this change:** no, not every song in
Apple Music has a BPM attached. Music does not analyse tempo: the BPM
field comes from the track's own metadata and is often blank,
especially for rips, older files, and sources that never wrote a
tempo tag. That is a metadata gap, not a bug in the shuffle, and the
fallback above is built for exactly that case.

**Before/after, on a varied 10-song missing-BPM fixture (run here):**

- Before: 50, 65, 63, 58, 58, 38, 55, 50, 65, 50 — 6 distinct
  values, three songs stuck at exactly 50.
- After: 48, 64, 64, 58, 55, 38, 57, 50, 69, 60 — 9 distinct
  values over 38-69, with only the truly blank song (unknown genre,
  no plays, no rating, not favorited) still at 50.
- The fallback spread is deliberately narrower than the BPM range:
  without a tempo, plays and genre are weak signals, and a wide
  spread would be guessing a tempo, not measuring one.

**What was actually tested here (Linux VM, Python 3.12.3):**

```bash
python3 -m unittest discover -s tests -v
# Ran 41 tests in 0.541s — OK
```

41 passed, 0 failed (31 pre-existing, all still passing, plus 10
new). New coverage: audit counts matching the sample fixture
(including BPM zero vs missing), audit CLI leaving the fixture
untouched, the missing-BPM spread, gospel/Christian/worship/praise/
latin/afrobeats/soundtrack mapping, BPM-present parity (including a
gospel BPM track scoring exactly as before), the skip penalty
applying only without BPM, skip-heavy songs staying Flow-eligible,
and the tie-break being deterministic. Shell syntax of `run.sh` and
`check-python.sh` checked with `bash -n`.

**What the Mac run must prove (still unverified):**

- `./run.sh audit` on Spencer's real library: the BPM present
  percentage and the top raw genres. If BPM present is 0%, the dump
  script is the prime suspect, not the library. If it is a small
  non-zero share, the library really lacks BPM and the fallback is
  the right fix. The top genres list also tells whether the new
  genre map covers what he actually has, or needs another pass.
- `./run.sh flowPreview` after the fallback: energies should spread
  instead of clumping at 50, and the arc should visibly rise and
  fall. If they still clump, the audit's genre/plays data will show
  why (for example, if his plays and ratings are also mostly blank).
- Everything from the first build's unverified list (bridge scripts,
  runner end to end, undo) remains unverified: no Mac run of those
  has happened from here.

## 2026-10-28 — Python core, first build (based on v2.6 + Flow)

**What it is:** the shuffle, Rediscover, and Flow logic rewritten in
Python (standard library only) as a testable core, plus a thin
AppleScript bridge that is the only part talking to Music. Same
defaults, same safety idea, same models as the AppleScript builds;
the difference is that the logic can actually be executed and tested
on a machine without Music.

**What was built:**

- `seter_shuffle/` — settings (v2.6 + Flow defaults), track model and
  library-JSON loading (duplicate persistent IDs rejected, unparseable
  dates treated as missing), artist keys (featuring counts as the main
  artist), Fisher-Yates shuffle with the v2.6 artist-spacing repair
  pass, Rediscover eligibility/weights/sampling (liked x forgotten,
  favorited x3, 4-5 stars x2, 1-2 stars x0.25, divided by 1+skips,
  forgotten multiplier capped at 5x, max 3 per artist, 14-day cooldown
  with relax-then-fill passes, picks shuffled and artist-spread),
  Flow energy (BPM bands, genre nudges, plays/rating/favorited, clamped
  5..100), Flow genre groups and related pairs, the wave arc (45 start,
  90 peak at two-thirds, 40 end), and the greedy nearest-neighbour
  walk (energy distance + genre cost + year cost + 1000 spacing
  penalty, ties keep the earliest song).
- CLI (`python3 -m seter_shuffle.cli`): `shuffle`,
  `rediscover`, `rediscover-preview`, `flow`, `flowPreview`
  (plus `flow-preview` alias), and `record-history`. The core reads a
  library JSON dump and writes an ordered-ID JSON and/or a
  one-ID-per-line text file. Preview commands never touch Music and
  never write history; `rediscover` does not write history either.
- Bridge (`bridge/`): `dump-library.applescript` (read-only dump of a
  library or playlist to JSON, dates as ISO from date components),
  `apply-order.applescript` (backup file written BEFORE any change,
  build from library by persistent ID, verify count + every expected
  ID, restore on any failure, regular user playlists only, library
  shrink check), `undo.applescript` (replay a backup file, loud on
  partial restores).
- Runner (`run.sh`) and `check-python.sh`: the runner wires
  bridge -> core -> bridge, logs under
  `~/Library/Logs/seter-shuffle-python/`, records Rediscover history
  only after a successful apply, and fails before touching Music if
  no real python3 (3.9+) is found. `run.sh` never touches the stable
  install or its launchd job.
- Tests (`tests/test_core.py`, fixture `tests/fixtures/sample-library.json`).

**What was actually tested here (Linux VM, Python 3.12.3):**

```bash
python3 -m unittest discover -s tests -v
# Ran 31 tests in 0.542s — OK
```

31 passed, 0 failed. Coverage includes: missing BPM, missing genre,
0/1/2-song Flow, artist spacing, featuring handling, disliked and
unchecked exclusion (both modes), skip-heavy exclusion (Rediscover
only) versus inclusion (Flow), Rediscover max-per-artist and cooldown,
history roundtrips, Flow arc targets and tie handling, energy clamps,
and CLI previews proving the input file is left byte-identical.
Shell syntax of both scripts was checked with `bash -n`. Two genuine
bugs were found and fixed during this build: the CLI `__main__`
guard was placed before `main()` was defined, and the runner parsed
the check script's "path (version)" output as the interpreter path.
One test expectation was also corrected during review: with
spacing=2, at least 2 songs must sit between repeats, so two artists
alone can never satisfy it; the test now uses three artists and
asserts the best-effort contract (never increases clash count) instead
of an impossible separation.

**What the Mac run must prove (bridge constructs, all unverified):**

- Dump script: bulk reads of `bpm`, `year`, `played date`, and
  `date added` over a playlist reference; `favorited` with the `loved`
  fallback; `month as integer` and the date-component ISO formatting;
  JSON escaping of unusual metadata (quotes, backslashes, newlines).
- Apply script: `first track of library playlist 1 whose persistent
  ID is ...` lookup; that duplicating tracks in order actually yields
  that order in the playlist; the verify step (count + presence);
  restore from backup after a forced failure; refusal of smart
  playlists; behaviour when a wanted ID is missing from the library.
- Undo script: restoring a real playlist from a real backup file,
  including the empty-backup (first-run playlist) case.
- Runner end to end: `check-python.sh` against the Mac's actual
  python3 (including what the stub does on that machine),
  `flowPreview` output, a real `flow` apply, the run log, and undo.
- Cross-check: a Python Flow order and an AppleScript Flow order from
  the same library should agree closely (identical, given the same
  pool draw and seed handling, is not expected: the AppleScript pool
  draw and the Python pool draw use different random sources).

**Known limits (honest list):**

- The bridge cannot be executed here (no osascript, no Music), so
  nothing in `bridge/` has run at all. Treat it as reviewed, not tested.
- Python Flow and AppleScript Flow will not produce byte-identical
  orders from the same library unless the pool draws coincide; the
  models match, the random sources do not.
- The dump script's JSON escaping handles backslash, quote, newline,
  carriage return, and tab; exotic control characters in metadata are
  not specially escaped.
- Rediscover weights for songs dated in the future would go negative
  in theory; the core drops non-positive weights rather than feeding a
  negative weight into the cumulative sampler (v2.6's sampler would
  misbehave there too, and no real library should have future dates).
- The runner's backup filenames are derived from playlist names by
  replacing spaces and slashes with underscores; two playlists whose
  names differ only by those characters would share a backup file.
  Playlist names with newlines would also break the line-based
  interchange files. Both are edge cases, flagged here rather than
  hidden.
