# Experimental changelog

This file tracks experimental builds only. Stable releases (v2.6 is current
stable) are untouched by anything here. Experimental builds are published as
prereleases, never as stable releases, and are never auto-installed on a Mac.

## 2026-10-28 — Flow mode (first experimental build, based on v2.6)

**What it is:** a new curated playlist mode. Instead of shuffling, Flow
orders songs so the vibe flows: it starts mid-energy, rises to a peak around
two-thirds through, then eases down at the end. It builds or refreshes a
playlist called "SeTeR Flow".

**New commands** (from the folder holding the experimental script):

```bash
/usr/bin/osascript SeTeR-shuffle.applescript flowPreview
/usr/bin/osascript SeTeR-shuffle.applescript flow
```

`flowPreview` prints the would-be order (first 25 songs, with energy scores)
and changes nothing. `flow` writes the "SeTeR Flow" playlist. Flow is also
in the double-click app menu as "🌊 Flow". It is not part of the daily run:
the daily run still only shuffles the daily playlist and refreshes
"SeTeR Rediscover".

**Source:** the whole library, not the daily playlist, so there is enough
variety to shape an arc. Eligible songs are checked (not unchecked) and not
disliked. Unlike Rediscover, skip-heavy songs are not excluded: a Flow set
is about vibe, and a skipped song can still fit the arc.

**Energy model, in plain words:**

| Signal | Effect on the 5..100 energy score |
|---|---|
| BPM | Sets the base: under 80 = 25, 80-99 = 40, 100-119 = 55, 120-139 = 75, 140-159 = 85, 160+ = 95. Missing BPM = 50 (mid-energy, never 0). |
| Genre | Rock/metal/punk/alternative or pop/dance/electronic +8; hip-hop/rap/R&B +5; jazz/soul/funk/blues -5; country/folk -3; classical/ambient/instrumental/lo-fi -12; anything else 0. |
| Plays | 20+ plays +5. |
| Rating | 4-5 stars (80-100) +5; 1-2 stars (1-40) -10; unrated 0. |
| Favorited | +5. |

The score is clamped to 5..100, so no single missing field can zero or max
a song out.

**Sequencing:** a greedy nearest-neighbor walk along a wave arc (45 at the
start, 90 at the two-thirds peak, 40 at the end). Each step picks the
remaining song with the lowest cost, where cost = distance from the arc
target + genre cost (0 for the same genre group, 8 for a related group,
20 otherwise) + year cost (0 for the same decade, 5 for an adjacent decade,
10 otherwise) + 1000 if the artist appeared within the last `artistSpacing`
songs (so artist spacing wins over vibe, best effort). Ties keep the
earliest song in the pool.

**Settings** (top of the script): `flowSize` (default 50, max songs in
"SeTeR Flow") and `flowPoolMax` (default 400, the random pool the greedy
pass sequences from when the library is bigger, so ordering stays fast).

**Safety — same path as stable, no new one:** Flow writes only through the
existing `rewritePlaylistSafely` handler: snapshot the playlist's persistent
IDs before changing anything, build, verify the count and every expected ID
afterwards, and restore from the snapshot on any failure. The library-size
check inside `buildPlaylist` also runs, and only regular user playlists are
touched (`assertUserPlaylist`). `flowPreview` changes nothing in Music.

**Known limits (honest list):**

- NOT TESTED. This build was written and reviewed on a Linux VM with no
  Music app and no `osascript`, so nothing here has actually run. The Mac
  run must prove it: first `flowPreview`, then `flow` on a test library
  if possible, and check the playlist order, the log, and that Undo still
  restores the previous "SeTeR Flow".
- BPM data in Apple Music is often missing or wrong, so many songs fall
  back to the mid-energy base plus genre nudges. Flow quality depends
  heavily on how complete the library's BPM and genre tags are.
- The greedy walk is not globally optimal: it picks the best next song,
  not the best whole playlist, so the arc can wobble if the pool lacks
  songs near a target energy.
- The pool is random when the library is large (up to 400 songs), so two
  Flow runs can pick different songs even with the same library.
- A 2-song Flow ends at the peak instead of easing down (the arc needs at
  least 3 songs to have a rise and a fall).
- Genre grouping is substring matching ("rock" matches "Rock", "Punk Rock",
  and also any genre containing those words), so odd genre tags can land
  in the wrong group.
- "SeTeR Flow" is a new playlist: on first run it is created empty and
  then filled, so there is nothing meaningful to undo back to.
- Flow does not use duration, key, loudness, or any audio analysis: only
  the Music track properties listed above exist in AppleScript, and none
  of those were invented.
