# Experimental changelog, Python core

This file tracks the Python experimental build only. Stable releases
(v2.6 is current stable) are untouched by anything here, and so is the
AppleScript experimental build. The Python version is published, if at
all, as a prerelease, never as stable, and is never auto-installed on
a Mac. The daily stable run stays AppleScript.

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
