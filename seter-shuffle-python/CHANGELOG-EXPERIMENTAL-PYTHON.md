# Experimental changelog, Python core

This file tracks the Python experimental build only. Stable releases
(v2.6 is current stable) are untouched by anything here, and so is the
AppleScript experimental build. The Python version is published, if at
all, as a prerelease, never as stable, and is never auto-installed on
a Mac. The daily stable run stays AppleScript until Spencer approves
the exact stable change list for the proposed v3.0 promotion; this
entry is preparation for that decision, not the promotion itself.

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
