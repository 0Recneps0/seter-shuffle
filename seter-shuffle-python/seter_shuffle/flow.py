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
  lo-fi, 7 anything else, 8 gospel/christian/worship/praise/
  choir/choral,
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
- RELATIVE ARC, all-fallback pools only (2026-10-29 experimental):
  Spencer's 2026-10-29 audit showed a real library with BPM missing
  on 100% of tracks and fallback energies spanning only 47..68, so
  the fixed 45..90..40 arc aims at a peak the pool cannot reach and
  a tail below its floor. When every pool track is BPM-missing and
  the pool's energy range is at least 10, prepare_flow rescales the
  fixed arc into the pool's own [min, max] range instead: the start
  maps near the pool floor, the peak maps to the pool max, the end
  maps to the pool floor, so the wave rises and falls relative to
  what the pool can actually do. A pool with any BPM track keeps
  the fixed arc exactly, so BPM scoring stays byte-for-byte the
  AppleScript behaviour, and a narrow fallback range (<10) keeps
  the fixed arc rather than amplifying noise.
- GREEDY WALK, arc-first (2026-10-29 flow fix): each step picks the
  unused song with the lowest cost: |energy - arc target| + genre
  cost (0 same, 3 related, 8 otherwise) + year cost (0 same decade,
  2 adjacent decade, 4 otherwise) + 4 if its energy equals the
  previous pick's energy + 1000 if the artist appeared within the
  last `artist_spacing` picks, so spacing wins over vibe, best
  effort. The old genre cost (0/8/20) was the main flat-block cause:
  it outweighed the whole energy distance, so the walk stayed in
  one genre cluster at one energy for the first half and then
  jumped to a different cluster at the peak, a cliff instead of a
  wave. The smaller genre cost lets the arc target drive the walk
  while still preferring genre continuity on near-ties. On an exact
  cost tie, the walk prefers movement over library order: a genre
  group different from the previous pick first, then higher
  familiarity (plays, favorited, rating), then the earliest pool
  song, so the order is deterministic and flat-energy pools stop
  coming out in raw library order.
- DIRECTIONAL COST, arc-tracking (2026-11-05 experimental): the
  distance term alone is symmetric, so on a near-tie the walk could
  jump ahead of the arc on the rise (a hotter song than the target)
  or drop below it on the fall (a colder song than the target),
  making the actual sequence zigzag around the arc instead of
  tracking it. Each step now also adds a small +5 when the candidate
  sits on the wrong side of the target for the arc's direction at
  that position: above the target while the arc is rising, below it
  while the arc is falling. The direction comes from the arc targets
  themselves (next target vs current, previous target at the last
  slot), so the peak slot counts as falling and prefers not to
  undershoot the peak. +5 only breaks near-ties: a candidate 6+
  closer to the target still wins, and the 1000 artist-spacing
  penalty still wins over everything. A flat pool is unaffected:
  equal energies are penalised equally, so the ranking does not
  change.
- STRANDED-SONG RULE, arc-tracking (2026-11-17 experimental): the
  greedy walk is short-sighted about the tail. On the fall it can
  spend a slot on a cold song that fits a later target perfectly,
  leaving a hot song with no target left to land on, so the
  playlist ends on that hot song after the cold tail: a 7-song pool
  [40, 44, 56, 69, 72, 87, 91] came back [44, 56, 72, 91, 69, 40,
  87], ending on the 87. At each slot the walk now checks whether
  an unused song fits this slot clearly better than any later slot
  and fits no later slot well (best later fit >= 20 off, and >= 10
  worse than its fit now); such a stranded song is picked now, so
  the fall keeps falling. The thresholds keep the rule narrow:
  dense pools never trigger it, a pool with no cold tail at all is
  unchanged (the rule cannot invent one), and artist spacing (1000)
  still beats it (500), so a stranded song by a recently used
  artist still waits. The rescaled targets are used when arc_lo /
  arc_hi are set, so the rule fires under the relative arc too.
- VIBE SCORE, NOT A TEMPO (2026-10-29 flow fix): the fallback energy
  is renamed in spirit, not in code: it is a vibe/arc score built
  only from fields already in the library dump. It never claims to
  be BPM, and the BPM-present path is untouched. The fallback now
  also uses, in addition to the old genre group, tiered plays,
  rating, favorited, and skip penalty: genre raw-string subgroups
  inside group 8 (choir/choral calmer, worship/praise calmer,
  contemporary brighter), finer play-count tiers, finer skip-ratio
  bands plus a never-skipped bonus, a release-year era band, and,
  when the caller supplies a reference time, played-date recency
  and date-added newness. No field is invented, no network call is
  made, and no API key is involved.
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
import sys
from dataclasses import dataclass
from datetime import datetime
from typing import Callable, Mapping, Sequence

from .artists import artist_compare_key
from .settings import Settings
from .tracks import Track, dump_now


@dataclass(frozen=True)
class AiTag:
    """One AI-assigned vibe tag: energy 0..100 and an optional mood bucket."""

    energy: int
    mood: str | None = None


# Moods an AI tagger may return (ai_tags.MOODS mirrors this tuple) and
# which pairs sit next to each other on the vibe map. Same mood costs 0
# in the walk, a related mood costs half of Settings.ai_mood_cost, any
# other pair the full cost. Moods only matter when both neighbours have one.
MOODS: tuple[str, ...] = ("calm", "mellow", "upbeat", "driving", "dark", "euphoric")
_MOOD_RELATED: frozenset[frozenset[str]] = frozenset(
    frozenset(pair)
    for pair in (
        ("calm", "mellow"), ("mellow", "upbeat"), ("upbeat", "driving"),
        ("upbeat", "euphoric"), ("driving", "euphoric"), ("driving", "dark"),
        ("mellow", "dark"),
    )
)


def mood_cost(a: str | None, b: str | None, full: int) -> float:
    """Walk cost between two moods: 0 same/unknown, full/2 related, else full."""
    if full <= 0 or a is None or b is None or a == b:
        return 0.0
    return full / 2.0 if frozenset((a, b)) in _MOOD_RELATED else float(full)

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
    (8, ("gospel", "christian", "worship", "praise", "ccm", "contemporary christian",
         "choir", "choral")),
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
    """Missing-BPM familiarity tier: small steps, not a tempo claim.

    Finer than the 2026-10-28 tiers (0/2/4/6/9): the old tiers gave
    every low-play gospel track the same tier, which is half of why
    the real list clumped at 48. The steps stay small so plays never
    masquerade as tempo.
    """
    if played_count <= 0:
        return 0
    if played_count == 1:
        return 1
    if played_count <= 3:
        return 2
    if played_count <= 7:
        return 3
    if played_count <= 14:
        return 4
    if played_count <= 24:
        return 6
    if played_count <= 39:
        return 8
    if played_count <= 69:
        return 10
    return 12


def _gospel_subgroup_nudge(genre: str | None) -> int:
    """Vibe subgroup inside genre group 8, fallback path only.

    The old model gave every gospel/Christian track the same -2,
    which flattened a whole subculture into one energy. The raw
    genre string already distinguishes them, and the distinction is
    a vibe distinction (choir and worship read calmer, contemporary
    reads brighter), not a tempo measurement. Non-group-8 genres
    get 0 here; the group nudge already covers them.
    """
    if genre_group(genre) != 8 or not genre:
        return 0
    lowered = str(genre).lower()
    if "choir" in lowered or "choral" in lowered:
        return -4
    if "worship" in lowered or "praise" in lowered:
        return -2
    if "contemporary" in lowered:
        return 3
    return 0


def _year_band(year: int | None) -> int:
    """Release-era band: recent eras read brighter, older read calmer.

    Calendar-year bands only, so the result never drifts with the
    clock. This is an era/vibe signal, not a tempo claim.
    """
    if year is None:
        return 0
    if year >= 2020:
        return 2
    if year >= 2010:
        return 1
    if year >= 2000:
        return 0
    if year >= 1990:
        return -1
    return -2


def _recency_nudge(track: Track, now: datetime | None) -> int:
    """Played-date / date-added nudge, only when `now` is supplied.

    Direct flow_energy calls without `now` stay deterministic (no
    recency contribution); prepare_flow supplies the real clock, and
    tests supply a fixed clock. Recently played reads as current,
    long-unplayed reads as stale, recently added reads as new.
    """
    if now is None:
        return 0
    nudge = 0
    if track.played_date is not None:
        days = (now - track.played_date).days
        if days < 0:
            days = 0
        if days <= 30:
            nudge += 3
        elif days <= 180:
            nudge += 1
        elif days > 730:
            nudge -= 2
    if track.date_added is not None:
        added_days = (now - track.date_added).days
        if 0 <= added_days <= 90:
            nudge += 2
    return nudge


def _skip_nudge(track: Track) -> int:
    """Skip-ratio band, fallback path only (BPM path has no skip term).

    Mostly-skipped tracks score lower, never-skipped well-played
    tracks score a little higher. Skip-heavy songs stay eligible;
    this is a score, not an exclusion.
    """
    total = track.played_count + track.skipped_count
    if total >= 3:
        ratio = track.skipped_count / total
        if ratio > 0.9:
            return -8
        if ratio > 0.5:
            return -5
        if ratio >= 0.25:
            return -2
    if track.played_count >= 10 and track.skipped_count == 0:
        return 2
    return 0


def familiarity(track: Track) -> int:
    """Tie-break familiarity: plays (capped) + favorited + rating stars."""
    return min(track.played_count, 100) + (25 if track.favorited else 0) + track.rating // 20


def flow_energy(track: Track, now: datetime | None = None) -> int:
    """Vibe/energy score 5..100. Never a tempo claim when BPM is missing.

    With BPM: exactly the AppleScript formula (BPM bands, legacy
    genre nudges, single >=20 plays step, rating, favorited), and
    nothing else: no subgroup, year, recency, or skip term touches
    this path, so BPM-present scores are byte-for-byte unchanged.
    Without BPM: base 50, expanded genre nudge plus the group-8
    subgroup nudge, finer tiered plays, rating (3 stars +2,
    4-5 stars +5, 1-2 stars -10), favorited +5, finer skip bands
    plus a never-skipped bonus, a release-year era band, and, when
    `now` is supplied, played-date recency and date-added newness.
    Skip-heavy songs are still eligible; they just do not score
    like never-skipped ones.
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
    energy += _gospel_subgroup_nudge(track.genre)
    energy += _played_tier(track.played_count)
    if track.rating >= 80:
        energy += 5
    elif track.rating >= 60:
        energy += 2
    elif 1 <= track.rating <= 40:
        energy -= 10
    if track.favorited:
        energy += 5
    energy += _skip_nudge(track)
    energy += _year_band(track.year)
    energy += _recency_nudge(track, now)
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


def flow_arc_summary(energies: Sequence[int]) -> str | None:
    """One-line summary of a Flow order's energy arc, for previews only.

    The preview prints only the first `preview_show` songs, so a flat
    first page used to hide whether the full order actually rises and
    falls. This line covers the whole ordered list: its size, its
    energy range, its first and last energies, and where the peak
    lands (the first position at the maximum, 1-based). It changes
    nothing: it only describes an order already computed.
    """
    if not energies:
        return None
    peak = max(energies)
    peak_pos = list(energies).index(peak) + 1
    noun = "song" if len(energies) == 1 else "songs"
    return (
        f"Flow arc: {len(energies)} {noun}, energies "
        f"{min(energies)}..{peak}, starts {energies[0]}, "
        f"peaks {peak} at #{peak_pos}, ends {energies[-1]}."
    )


def _arc_target(
    position: int, total: int, arc_lo: int | None, arc_hi: int | None
) -> float:
    """Arc target at a position, optionally rescaled to [arc_lo, arc_hi].

    The fixed arc runs 40..90 (end..peak), so rescaling is
    lo + (fixed - 40) / 50 * (hi - lo): the fixed start (45) lands
    near the pool floor, the fixed peak (90) lands on the pool max,
    and the fixed end (40) lands on the pool floor. A missing bound
    or a range under 10 keeps the fixed target unchanged.
    """
    fixed = flow_target_energy(position, total)
    if arc_lo is None or arc_hi is None or arc_hi - arc_lo < 10:
        return fixed
    return arc_lo + (fixed - 40.0) / 50.0 * (arc_hi - arc_lo)


def _arc_direction(
    position: int, total: int, arc_lo: int | None, arc_hi: int | None
) -> int:
    """Arc direction at a 1-based position: +1 rising, -1 falling, 0 flat.

    Compares the arc target at this position with the next one (with
    the previous one at the last slot, where there is no next). The
    peak slot therefore counts as falling, since the target after it
    is lower. A single-song Flow has no direction. The rescaled
    targets are used when arc_lo/arc_hi are set, so the direction
    matches what the walk actually aims at.
    """
    if total <= 1:
        return 0
    current = _arc_target(position, total, arc_lo, arc_hi)
    if position < total:
        # Direction of travel out of this slot: toward the next target.
        nxt = _arc_target(position + 1, total, arc_lo, arc_hi)
        if nxt > current:
            return 1
        if nxt < current:
            return -1
        return 0
    # Last slot: no next target, so the direction is the direction of
    # arrival: the current target compared with the previous one.
    prev = _arc_target(position - 1, total, arc_lo, arc_hi)
    if current > prev:
        return 1
    if current < prev:
        return -1
    return 0


# Wrong-side-of-the-arc cost (see the DIRECTIONAL COST docstring
# above). Small on purpose: it breaks near-ties toward a smoother
# climb and fall, never overruling a clearly closer arc match (a
# candidate 6+ closer still wins) or artist spacing (1000).
_DIRECTION_PENALTY = 5

# Stranded-song rule (see the STRANDED-SONG RULE docstring above).
# A song is stranded at a slot when its best fit among the later
# targets is bad (>= _STRANDED_MIN_LATER_MISS off) and clearly
# worse than its fit at this slot (>= _STRANDED_IMPROVEMENT worse),
# so picking anything else now wastes the song's last good home.
# _STRANDED_PENALTY sits between the vibe terms (at most ~21
# combined) and artist spacing (1000): it forces the stranded pick
# over any vibe consideration, but spacing still wins over it.
_STRANDED_MIN_LATER_MISS = 20
_STRANDED_IMPROVEMENT = 10
_STRANDED_PENALTY = 500


def flow_order(
    energies: list[int],
    groups: list[int],
    years: list[int | None],
    artist_keys: list[str],
    total: int,
    spacing: int,
    familiarity: list[int] | None = None,
    arc_lo: int | None = None,
    arc_hi: int | None = None,
    moods: list[str | None] | None = None,
    mood_weight: int = 0,
) -> list[int]:
    """Greedy Flow order as pool indices.

    On an exact cost tie, prefer a genre group different from the
    previous pick (movement over library order), then higher
    familiarity, then the earliest pool song, so ties are
    deterministic instead of silently returning library order.
    With arc_lo/arc_hi, the arc targets are rescaled into that
    range (see _arc_target); without them, the fixed 45..90..40
    arc is used exactly as before. A candidate on the wrong side
    of the target for the arc's direction at that position (above
    it while rising, below it while falling) costs an extra
    _DIRECTION_PENALTY, so near-ties resolve toward a smoother
    climb and fall instead of a zigzag around the arc. A stranded
    song (one that fits this slot clearly better than any later
    slot and fits no later slot well) is picked now: any other
    candidate costs an extra _STRANDED_PENALTY, so the walk does
    not waste a slot on a song with a good home later and leave a
    hot song with nowhere to land at the end.
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
    prev_energy: int | None = None
    prev_mood: str | None = None
    for position in range(1, total + 1):
        target = _arc_target(position, total, arc_lo, arc_hi)
        direction = _arc_direction(position, total, arc_lo, arc_hi)
        # Stranded songs for this slot: unused songs whose best fit
        # among the later targets is bad and clearly worse than
        # their fit here. With no later slots there is nothing to
        # strand against, so the set stays empty at the last slot.
        later_targets = [
            _arc_target(p, total, arc_lo, arc_hi)
            for p in range(position + 1, total + 1)
        ]
        stranded: set[int] = set()
        if later_targets:
            for i in range(n):
                if used[i]:
                    continue
                fit_now = abs(energies[i] - target)
                fit_later = min(
                    abs(energies[i] - t) for t in later_targets
                )
                if (
                    fit_later >= _STRANDED_MIN_LATER_MISS
                    and fit_later - fit_now >= _STRANDED_IMPROVEMENT
                ):
                    stranded.add(i)
        best_idx = -1
        best_key: tuple[float, int, int, int] | None = None
        for i in range(n):
            if used[i]:
                continue
            cost = abs(energies[i] - target)
            # Directional cost: on the rise, a song hotter than the
            # target jumps ahead of the arc; on the fall, a song
            # colder than the target drops below it early. Either
            # way the sequence zigzags around the arc instead of
            # tracking it, so the wrong side costs a little extra.
            if direction > 0 and energies[i] > target:
                cost += _DIRECTION_PENALTY
            elif direction < 0 and energies[i] < target:
                cost += _DIRECTION_PENALTY
            if prev_group is not None:
                if groups[i] == prev_group:
                    pass
                elif genres_related(groups[i], prev_group):
                    cost += 3
                else:
                    cost += 8
            if prev_year is not None and years[i] is not None:
                decade_diff = abs((prev_year // 10) * 10 - (years[i] // 10) * 10)
                if decade_diff == 0:
                    pass
                elif decade_diff == 10:
                    cost += 2
                else:
                    cost += 4
            # Break flat blocks: repeating the exact previous energy
            # costs a little, so a pool of identical scores cannot
            # fill half the playlist before the arc moves.
            if prev_energy is not None and energies[i] == prev_energy:
                cost += 4
            if moods is not None and mood_weight > 0:
                cost += mood_cost(prev_mood, moods[i], mood_weight)
            # Stranded-song rule: when a stranded song exists, any
            # other pick wastes this slot on a song with a good home
            # later and strands the hot song at the end. The 500
            # penalty beats every vibe term but not artist spacing.
            if stranded and i not in stranded:
                cost += _STRANDED_PENALTY
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
        prev_energy = energies[best_idx]
        prev_mood = moods[best_idx] if moods is not None else None
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
    now: datetime | None = None,
    tagger: Callable[[list[Track]], Mapping[str, AiTag]] | None = None,
) -> tuple[list[Track], list[int], int]:
    """Order eligible tracks for a Flow playlist.

    Returns (ordered tracks, their energy scores in order, eligible
    count). The ordered list is capped at flow_size (minimum 1, matching
    the AppleScript build) and at the pool size. `now` is the reference
    time for the played-date / date-added recency nudge; when omitted
    the dump-frame clock is used (see tracks.dump_now), and tests pass
    a fixed clock.

    `tagger` is optional AI tagging (ai_tags.FlowTagger): it receives
    only the pool tracks (never the whole library) and returns
    {persistent_id: AiTag} for the ones it could tag. A tagged track's
    energy becomes a blend of the AI energy and the heuristic energy
    (Settings.ai_blend) and its mood joins the walk cost; an untagged
    track keeps its heuristic energy exactly, so a tagger that fails or
    knows nothing leaves Flow identical to a run without one. The
    tagger is only called when Settings.ai_enabled is true, and an
    exception from it never fails Flow.
    """
    rng = rng or random.Random()
    if now is None:
        now = dump_now()
    eligible = [t for t in tracks if t.enabled and not t.disliked]
    if not eligible:
        return [], [], 0
    energies = [flow_energy(t, now=now) for t in eligible]
    groups = [genre_group(t.genre) for t in eligible]
    years = [t.year for t in eligible]
    keys = [
        artist_compare_key(t.artist, settings.featuring_is_same_artist, settings.split_collabs)
        for t in eligible
    ]
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
    pool_moods: list[str | None] | None = None
    if tagger is not None and settings.ai_enabled:
        tags: Mapping[str, AiTag] = {}
        try:
            tags = tagger([eligible[i] for i in pool]) or {}
        except Exception as exc:  # AI is optional: it must never fail Flow
            print(f"warning: AI tagging failed, using heuristic energy ({exc})", file=sys.stderr)
        blend = max(0.0, min(1.0, settings.ai_blend))
        pool_moods = []
        for k, i in enumerate(pool):
            tag = tags.get(eligible[i].persistent_id)
            if tag is None:
                pool_moods.append(None)
                continue
            mixed = round(blend * tag.energy + (1.0 - blend) * pool_energies[k])
            pool_energies[k] = max(5, min(100, mixed))
            pool_moods.append(tag.mood)
    want = max(1, settings.flow_size)
    # Relative arc only for an all-fallback pool: every pool track
    # BPM-missing, with enough spread to rescale meaningfully. Any
    # BPM track in the pool keeps the fixed arc (BPM parity).
    pool_tracks = [eligible[i] for i in pool]
    arc_lo = arc_hi = None
    if pool_energies and all(
        t.bpm is None or t.bpm <= 0 for t in pool_tracks
    ):
        lo, hi = min(pool_energies), max(pool_energies)
        if hi - lo >= 10:
            arc_lo, arc_hi = lo, hi
    order = flow_order(
        pool_energies,
        pool_groups,
        pool_years,
        pool_keys,
        want,
        settings.artist_spacing,
        familiarity=pool_fams,
        arc_lo=arc_lo,
        arc_hi=arc_hi,
        moods=pool_moods,
        mood_weight=settings.ai_mood_cost,
    )
    ordered = [eligible[pool[i]] for i in order]
    ordered_energies = [pool_energies[i] for i in order]
    return ordered, ordered_energies, len(eligible)
