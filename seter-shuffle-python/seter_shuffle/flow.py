"""Flow ordering: a curated playlist that flows with the songs' vibes.

Ported from the experimental AppleScript Flow build (2026-10-28), with
no change to the model:

- ENERGY 5..100 from BPM bands, genre nudges, plays, rating, favorited.
  Missing BPM defaults to 50 (mid-energy, never 0). Missing genre is
  group 7 (no nudge).
- GENRE GROUPS by substring matching, in this order: 1 rock/metal/punk/
  alternative, 2 hip-hop/rap/R&B, 3 pop/dance/electronic, 4 jazz/soul/
  funk/blues, 5 country/folk/americana, 6 classical/ambient/instrumental/
  lo-fi, 7 anything else. Related pairs: 1-3, 2-3, 4-6, 5-6.
- WAVE ARC target: 45 at the start, 90 at the two-thirds peak, 40 at
  the end. (A 2-song Flow ends at the peak: the arc needs at least
  3 songs to rise and fall. That quirk is preserved, not fixed here,
  so the Python output matches the AppleScript output.)
- GREEDY WALK: each step picks the unused song with the lowest cost:
  |energy - arc target| + genre cost (0 same, 8 related, 20 otherwise)
  + year cost (0 same decade, 5 adjacent decade, 10 otherwise)
  + 1000 if the artist appeared within the last `artist_spacing`
  picks, so spacing wins over vibe, best effort. Ties keep the
  earliest pool song.
- ELIGIBLE: checked (enabled) and not disliked. Unlike Rediscover,
  skip-heavy songs are NOT excluded: a Flow set is about vibe, and a
  skipped song can still fit the arc. This is deliberate and matches
  the AppleScript build.
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
_GENRE_GROUPS: tuple[tuple[int, tuple[str, ...]], ...] = (
    (1, ("metal", "punk", "rock", "alternative")),
    (2, ("hip-hop", "hip hop", "rap", "r&b", "rhythm")),
    (3, ("dance", "electronic", "edm", "pop")),
    (4, ("jazz", "soul", "funk", "blues")),
    (5, ("country", "folk", "americana")),
    (6, ("classical", "ambient", "instrumental", "lo-fi", "lofi", "chill")),
)

_RELATED: frozenset[tuple[int, int]] = frozenset(
    {(1, 3), (3, 1), (2, 3), (3, 2), (4, 6), (6, 4), (5, 6), (6, 5)}
)


def genre_group(genre: str | None) -> int:
    """Genre group 1..7 by substring matching (case-insensitive)."""
    if not genre:
        return 7
    lowered = str(genre).lower()
    for group, needles in _GENRE_GROUPS:
        if any(needle in lowered for needle in needles):
            return group
    return 7


def genres_related(group_a: int, group_b: int) -> bool:
    """Same group, or one of the related pairs."""
    return group_a == group_b or (group_a, group_b) in _RELATED


def flow_energy(track: Track) -> int:
    """Energy score 5..100 from BPM, genre, plays, rating, favorited."""
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
    else:
        energy = 50
    group = genre_group(track.genre)
    if group in (1, 3):
        energy += 8
    elif group == 2:
        energy += 5
    elif group == 4:
        energy -= 5
    elif group == 5:
        energy -= 3
    elif group == 6:
        energy -= 12
    if track.played_count >= 20:
        energy += 5
    if track.rating >= 80:
        energy += 5
    elif 1 <= track.rating <= 40:
        energy -= 10
    if track.favorited:
        energy += 5
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
) -> list[int]:
    """Greedy Flow order as pool indices (ties keep the earliest song)."""
    n = len(energies)
    total = min(total, n)
    if total <= 0:
        return []
    used = [False] * n
    order: list[int] = []
    recent: list[str] = []
    prev_group: int | None = None
    prev_year: int | None = None
    for position in range(1, total + 1):
        target = flow_target_energy(position, total)
        best_idx = -1
        best_cost = float("inf")
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
            if cost < best_cost:
                best_cost = cost
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
    if settings.flow_pool_max > 0 and len(eligible) > settings.flow_pool_max:
        pool = rng.sample(range(len(eligible)), settings.flow_pool_max)
    else:
        pool = list(range(len(eligible)))
    pool_energies = [energies[i] for i in pool]
    pool_groups = [groups[i] for i in pool]
    pool_years = [years[i] for i in pool]
    pool_keys = [keys[i] for i in pool]
    want = max(1, settings.flow_size)
    order = flow_order(
        pool_energies, pool_groups, pool_years, pool_keys, want, settings.artist_spacing
    )
    ordered = [eligible[pool[i]] for i in order]
    ordered_energies = [pool_energies[i] for i in order]
    return ordered, ordered_energies, len(eligible)
