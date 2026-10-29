"""Flow ordering: a curated playlist that flows with the songs' vibes.

Ported from the experimental AppleScript Flow build (2026-10-28), with
one later change: the missing-BPM fallback (2026-10-28, see below).
Songs that DO have BPM score exactly as in the AppleScript build.

- ENERGY 5..100. With BPM, the BPM bands set the base and the old
  genre nudges, the single >=20 plays step, rating, and favorited
  nudges apply unchanged. Without BPM, the base is 50 and a fallback
  model applies instead (see `flow_energy`): an expanded genre map,
  tiered plays, rating, favorited, and a small skip-ratio penalty.
  The fallback spread is deliberately narrower than the BPM range:
  without a tempo, plays and genre are weak signals, and inventing a
  wide spread would be guessing a tempo, not measuring one.
- BPM IS NOT GUARANTEED. Apple Music does not analyse tempo for you:
  the BPM field comes from the track's own metadata, and it is often
  blank (rips, older files, sources that never wrote a tempo tag).
  A library full of missing BPM is normal metadata, not proof the
  dump failed; the `audit` command is how a Mac run tells the two
  apart (some BPM present = dump works, rest truly missing).
- GENRE GROUPS by substring matching, in this order: 1 rock/metal/punk/
  alternative, 2 hip-hop/rap/R&B, 3 pop/dance/electronic, 4 jazz/soul/
  funk/blues, 5 country/folk/americana, 6 classical/ambient/instrumental/
  lo-fi, 7 anything else, 8 gospel/christian/worship/praise,
  9 latin/reggaeton/salsa, 10 afrobeats/reggae, 11 soundtrack/score.
  Group 7 stays "anything else" (it predates groups 8-11). Related
  pairs: 1-3, 2-3, 4-6, 5-6, 8-4 (gospel-soul), 9-3 (latin-dance),
  10-3 (afrobeats-dance), 11-6 (soundtrack-instrumental). Genre is a
  weak energy signal, so every nudge is small and documented in
  `flow_energy`; no genre is treated as a tempo.
- WAVE ARC target: 45 at the start, 90 at the two-thirds peak, 40 at
  the end. (A 2-song Flow ends at the peak: the arc needs at least
  3 songs to rise and fall. That quirk is preserved, not fixed here,
  so the Python output matches the AppleScript output.)
- GREEDY WALK: each step picks the unused song with the lowest cost:
  |energy - arc target| + genre cost (0 same, 8 related, 20 otherwise)
  + year cost (0 same decade, 5 adjacent decade, 10 otherwise)
  + 1000 if the artist appeared within the last `artist_spacing`
  picks, so spacing wins over vibe, best effort. On an exact cost
  tie, the walk prefers movement over library order: a genre group
  different from the previous pick first, then higher familiarity
  (plays, favorited, rating), then the earliest pool song, so the
  order is deterministic and flat-energy pools stop coming out in
  raw library order.
- ELIGIBLE: checked (enabled) and not disliked. Unlike Rediscover,
  skip-heavy songs are NOT excluded: a Flow set is about vibe, and a
  skipped song can still fit the arc. This is deliberate and matches
  the AppleScript build. (The fallback energy model does give
  heavily-skipped songs a small penalty; that is a score, not an
  exclusion.)
- POOL: when more songs are eligible than `flow_pool_max`, a random
  pool of that size is drawn first, so the greedy pass stays fast.
  Two Flow runs can therefore pick different songs from a big library.

An explicit rng makes the pool draw replayable in tests.
"""

from __future__ import annotations

import random
from typing import Sequence

from .artists import artist_key
from .settings import Settings
from .tracks import Track

# Substring groups, checked in this order (first match wins).
# Groups 1-6 are the original AppleScript groups; groups 8-11 were
# added for the missing-BPM fallback (2026-10-28) after Spencer's
# preview came back heavy on gospel/Christian tracks that matched
# nothing. Group 7 stays "anything else".
_GENRE_GROUPS: tuple[tuple[int, tuple[str, ...]], ...] = (
    (1, ("metal", "punk", "rock", "alternative")),
    (2, ("hip-hop", "hip hop", "rap", "r&b", "rhythm")),
    (3, ("dance", "electronic", "edm", "pop")),
    (4, ("jazz", "soul", "funk", "blues")),
    (5, ("country", "folk", "americana")),
    (6, ("classical", "ambient", "instrumental", "lo-fi", "lofi", "chill")),
    (8, ("gospel", "christian", "worship", "praise", "ccm", "contemporary christian")),
    (9, ("latin", "reggaeton", "salsa", "bachata", "regional mexican", "corrido")),
    (10, ("afrobeats", "afrobeat", "amapiano", "reggae", "dancehall")),
    (11, ("soundtrack", "score", "musical", "broadway")),
)

# Groups 1-6 only, for the BPM-present path, which must score exactly
# as the AppleScript build did (a gospel BPM track previously scored
# with no genre nudge, and still does on that path).
_LEGACY_GENRE_GROUPS: tuple[tuple[int, tuple[str, ...]], ...] = _GENRE_GROUPS[:6]

_RELATED: frozenset[tuple[int, int]] = frozenset(
    {
        (1, 3), (3, 1), (2, 3), (3, 2), (4, 6), (6, 4), (5, 6), (6, 5),
        (8, 4), (4, 8), (9, 3), (3, 9), (10, 3), (3, 10), (11, 6), (6, 11),
    }
)

# Genre nudges. Legacy nudges are the AppleScript values, used
# unchanged on the BPM-present path. Fallback nudges reuse them for
# groups 1-6 and add small values for the new groups: gospel is
# near-mid (slow worship and energetic choir pull opposite ways, so
# the nudge stays tiny), latin and afrobeats are dance-adjacent but
# not as strong as EDM, soundtrack is a little below mid.
_LEGACY_GENRE_NUDGE: dict[int, int] = {1: 8, 2: 5, 3: 8, 4: -5, 5: -3, 6: -12}
_FALLBACK_GENRE_NUDGE: dict[int, int] = {
    **_LEGACY_GENRE_NUDGE, 7: 0, 8: -2, 9: 6, 10: 4, 11: -3,
}


def _group_with(groups: tuple[tuple[int, tuple[str, ...]], ...], genre: str | None) -> int:
    if not genre:
        return 7
    lowered = str(genre).lower()
    for group, needles in groups:
        if any(needle in lowered for needle in needles):
            return group
    return 7


def genre_group(genre: str | None) -> int:
    """Genre group by substring matching (case-insensitive)."""
    return _group_with(_GENRE_GROUPS, genre)


def genres_related(group_a: int, group_b: int) -> bool:
    """Same group, or one of the related pairs."""
    return group_a == group_b or (group_a, group_b) in _RELATED


def _played_tier(played_count: int) -> int:
    """Missing-BPM familiarity tier: small steps, not a tempo claim."""
    if played_count <= 0:
        return 0
    if played_count <= 4:
        return 2
    if played_count <= 19:
        return 4
    if played_count <= 49:
        return 6
    return 9


def familiarity(track: Track) -> int:
    """Tie-break familiarity: plays (capped) + favorited + rating stars."""
    return min(track.played_count, 100) + (25 if track.favorited else 0) + track.rating // 20


def flow_energy(track: Track) -> int:
    """Energy score 5..100.

    With BPM: exactly the AppleScript formula (BPM bands, legacy
    genre nudges, single >=20 plays step, rating, favorited).
    Without BPM: base 50, expanded genre nudge, tiered plays,
    rating (3 stars +2, 4-5 stars +5, 1-2 stars -10), favorited +5,
    and a -5 skip penalty only when at least 3 plays+skips exist
    and more than half were skips. Skip-heavy songs are still
    eligible; they just do not score like never-skipped ones.
    """
    if track.bpm is not None and track.bpm > 0:
        bpm = track.bpm
        if bpm < 80:
            energy = 25
        elif bpm < 100:
            energy = 40
        elif bpm < 120:
            energy = 55
        elif bpm < 140:
            energy = 75
        elif bpm < 160:
            energy = 85
        else:
            energy = 95
        energy += _LEGACY_GENRE_NUDGE.get(
            _group_with(_LEGACY_GENRE_GROUPS, track.genre), 0
        )
        if track.played_count >= 20:
            energy += 5
        if track.rating >= 80:
            energy += 5
        elif 1 <= track.rating <= 40:
            energy -= 10
        if track.favorited:
            energy += 5
        return max(5, min(100, energy))
    energy = 50
    energy += _FALLBACK_GENRE_NUDGE.get(genre_group(track.genre), 0)
    energy += _played_tier(track.played_count)
    if track.rating >= 80:
        energy += 5
    elif track.rating >= 60:
        energy += 2
    elif 1 <= track.rating <= 40:
        energy -= 10
    if track.favorited:
        energy += 5
    total_listens = track.played_count + track.skipped_count
    if total_listens >= 3 and track.skipped_count * 2 > total_listens:
        energy -= 5
    return max(5, min(100, energy))


def flow_target_energy(position: int, total: int) -> float:
    """Wave-arc target at 1-based `position` of `total` (45..90..40)."""
    if total <= 1:
        return 50.0
    rise_end = (total * 2) // 3
    rise_end = max(2, min(total, rise_end))
    if position <= rise_end:
        if rise_end == 1:  # unreachable given the clamp; kept for parity
            return 90.0
        return 45.0 + 45.0 * (position - 1) / (rise_end - 1)
    if total == rise_end:
        return 90.0
    return 90.0 - 50.0 * (position - rise_end) / (total - rise_end)


def flow_order(
    energies: list[int],
    groups: list[int],
    years: list[int | None],
    artist_keys: list[str],
    total: int,
    spacing: int,
    familiarity: list[int] | None = None,
) -> list[int]:
    """Greedy Flow order as pool indices.

    On an exact cost tie, prefer a genre group different from the
    previous pick (movement over library order), then higher
    familiarity, then the earliest pool song, so ties are
    deterministic instead of silently returning library order.
    """
    n = len(energies)
    total = min(total, n)
    if total <= 0:
        return []
    familiarity = familiarity if familiarity is not None else [0] * n
    used = [False] * n
    order: list[int] = []
    recent: list[str] = []
    prev_group: int | None = None
    prev_year: int | None = None
    for position in range(1, total + 1):
        target = flow_target_energy(position, total)
        best_idx = -1
        best_key: tuple[float, int, int, int] | None = None
        for i in range(n):
            if used[i]:
                continue
            cost = abs(energies[i] - target)
            if prev_group is not None:
                if groups[i] == prev_group:
                    pass
                elif genres_related(groups[i], prev_group):
                    cost += 8
                else:
                    cost += 20
            if prev_year is not None and years[i] is not None:
                decade_diff = abs((prev_year // 10) * 10 - (years[i] // 10) * 10)
                if decade_diff == 0:
                    pass
                elif decade_diff == 10:
                    cost += 5
                else:
                    cost += 10
            key = artist_keys[i]
            if key != "" and key in recent:
                cost += 1000
            # Tie-break: different genre from the previous pick (0)
            # beats the same genre (1); no previous pick means all
            # candidates tie on this axis.
            moves = (
                0
                if prev_group is not None and groups[i] != prev_group
                else 1
            )
            candidate_key = (cost, moves, -familiarity[i], i)
            if best_key is None or candidate_key < best_key:
                best_key = candidate_key
                best_idx = i
        if best_idx < 0:
            break
        used[best_idx] = True
        order.append(best_idx)
        prev_group = groups[best_idx]
        prev_year = years[best_idx]
        key = artist_keys[best_idx]
        if key != "":
            recent.append(key)
            while len(recent) > spacing:
                recent.pop(0)
    return order


def prepare_flow(
    tracks: Sequence[Track],
    settings: Settings,
    rng: random.Random | None = None,
) -> tuple[list[Track], list[int], int]:
    """Order eligible tracks for a Flow playlist.

    Returns (ordered tracks, their energy scores in order, eligible
    count). The ordered list is capped at flow_size (minimum 1, matching
    the AppleScript build) and at the pool size.
    """
    rng = rng or random.Random()
    eligible = [t for t in tracks if t.enabled and not t.disliked]
    if not eligible:
        return [], [], 0
    energies = [flow_energy(t) for t in eligible]
    groups = [genre_group(t.genre) for t in eligible]
    years = [t.year for t in eligible]
    keys = [artist_key(t.artist, settings.featuring_is_same_artist) for t in eligible]
    fams = [familiarity(t) for t in eligible]
    if settings.flow_pool_max > 0 and len(eligible) > settings.flow_pool_max:
        pool = rng.sample(range(len(eligible)), settings.flow_pool_max)
    else:
        pool = list(range(len(eligible)))
    pool_energies = [energies[i] for i in pool]
    pool_groups = [groups[i] for i in pool]
    pool_years = [years[i] for i in pool]
    pool_keys = [keys[i] for i in pool]
    pool_fams = [fams[i] for i in pool]
    want = max(1, settings.flow_size)
    order = flow_order(
        pool_energies,
        pool_groups,
        pool_years,
        pool_keys,
        want,
        settings.artist_spacing,
        familiarity=pool_fams,
    )
    ordered = [eligible[pool[i]] for i in order]
    ordered_energies = [pool_energies[i] for i in order]
    return ordered, ordered_energies, len(eligible)
