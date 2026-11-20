"""True-random shuffle with v2.6 artist spacing.

Fisher-Yates is the shuffle (the same algorithm v2.6 uses); artist
spacing is the same repair pass v2.6 uses, ported faithfully rather than
reinvented:

- A song at position p "clashes" if the same artist key appears within
  the next `spacing` positions (spacing=1 means just not back-to-back).
  Empty artist keys never clash.
- For each clash, up to 30 random swap partners anywhere in the list are
  tried; a swap is kept only if it strictly reduces the local clash
  count. Up to 6 passes, with a 20,000-attempt global cap.
- A swap partner by the same artist as the clashing song is skipped
  without counting as a try: swapping two same-artist songs leaves
  every position's key unchanged, so it can never reduce the clash
  count, and counting it would burn tries exactly when one artist
  dominates the list and the repair pass needs them most. Draws per
  clash are capped at 300 (10x the try budget) so a degenerate draw
  stream cannot spin the loop; an artist owning ~90% of the list
  still gets its full 30 effective tries on average.
- When the random tries fail, a deterministic scan fallback (2026-11-19
  experimental) walks the partners in order and takes the first swap
  that strictly reduces the local clash count. Random draws can miss
  a reducing partner that exists: with 30 tries over a big list, a
  rare good partner is usually never drawn, so the pass used to give
  up on a clash a single swap would have fixed. The scan has its own
  budget (5,000 swap evaluations per call), separate from the
  random-try budget, so a long scan on one clash cannot starve the
  random tries for later clashes: a prototype sharing the 20,000
  budget made a 846-song, 300-of-one-artist pool worse (77.1 -> 91.0
  average clashes left), while the separate budget makes it better
  (77.1 -> 74.8). A clash the scan also cannot fix is still best
  effort: the pass gives up on it rather than looping forever.
- It is best effort by design: an artist who makes up most of the list
  cannot be fully separated, and the pass gives up rather than looping
  forever.

Both functions take an explicit random.Random so tests can seed them
and replay an exact order. Passing no rng uses SystemRandom-grade
randomness (random.Random() seeded from the OS).

`shuffle_summary` describes a shuffle order already computed: how
many songs, how many distinct artists, how many positions still
clash with the same artist within the spacing (the repair pass is
best effort, so clashes can remain), and the most songs by one
artist. It changes no order; it only makes the spacing result
visible, the same way the Flow arc and Rediscover pick summaries
do for their previews.
"""

from __future__ import annotations

import random
from typing import Sequence, TypeVar

from .artists import artist_compare_key

T = TypeVar("T")

_MAX_ATTEMPTS = 20000
_MAX_PASSES = 6
_TRIES_PER_CLASH = 30
_MAX_DRAWS_PER_CLASH = 300
# Deterministic scan fallback budget (see module docstring): swap
# evaluations the scan may spend per spread_artists call, separate
# from _MAX_ATTEMPTS so a long scan cannot starve the random tries.
_MAX_SCAN_EVALUATIONS = 5000


def fisher_yates(items: Sequence[T], rng: random.Random | None = None) -> list[T]:
    """Return a new list shuffled with Fisher-Yates; input is untouched."""
    rng = rng or random.Random()
    order = list(items)
    for i in range(len(order) - 1, 0, -1):
        j = rng.randrange(i + 1)
        order[i], order[j] = order[j], order[i]
    return order


def _clashes_at(order: list[int], keys: list[str], p: int, spacing: int) -> bool:
    """Does the item at 0-based position p clash with a nearby same artist?"""
    n = len(order)
    if p < 0 or p >= n - 1:
        return False
    key = keys[order[p]]
    if key == "":
        return False
    last = min(p + spacing, n - 1)
    for q in range(p + 1, last + 1):
        if keys[order[q]] == key:
            return True
    return False


def _local_clashes(
    order: list[int], keys: list[str], spacing: int, i: int, j: int
) -> int:
    """Clash count over positions a swap of i and j can change.

    Mirrors v2.6's localClashes: the `spacing` positions before each of
    i and j, plus each position itself. Positions outside the list do
    not clash (matching v2.6's clashesAt guard).
    """
    count = 0
    for p in range(i - spacing, i + 1):
        if _clashes_at(order, keys, p, spacing):
            count += 1
    for p in range(j - spacing, j + 1):
        if p < i - spacing or p > i:
            if _clashes_at(order, keys, p, spacing):
                count += 1
    return count


def spread_artists(
    order: list[int],
    keys: list[str],
    spacing: int,
    rng: random.Random | None = None,
) -> list[int]:
    """Repair same-artist clashes in an index order, best effort.

    `order` holds indices into `keys`. Returns a new list; the input
    list is not mutated. With spacing < 1 the order is returned as-is.
    When the random tries fail on a clash, a deterministic scan of the
    partners in order is tried before giving up on that clash (see
    the module docstring); the scan costs scan evaluations, not
    random-try attempts, so it cannot starve later clashes.
    """
    rng = rng or random.Random()
    n = len(order)
    if spacing < 1 or n < 2:
        return list(order)
    spacing = min(spacing, n - 1)
    result = list(order)
    attempts_left = _MAX_ATTEMPTS
    scans_left = _MAX_SCAN_EVALUATIONS
    last_bad = -1
    for _pass in range(_MAX_PASSES):
        bad = 0
        for p in range(n - 1):
            if _clashes_at(result, keys, p, spacing):
                fixed = False
                tries = 0
                for _draw in range(_MAX_DRAWS_PER_CLASH):
                    if tries >= _TRIES_PER_CLASH or attempts_left < 1:
                        break
                    j = rng.randrange(n)
                    # A same-artist partner can never change the clash
                    # count: swapping two songs by the same artist
                    # leaves every position's key unchanged, so the
                    # before/after check would always tie and revert.
                    # Skip it without burning a try or an attempt.
                    # j == p is the same case. The draw cap bounds
                    # the loop when one artist dominates the list.
                    if j == p or keys[result[j]] == keys[result[p]]:
                        continue
                    tries += 1
                    attempts_left -= 1
                    before = _local_clashes(result, keys, spacing, p, j)
                    result[p], result[j] = result[j], result[p]
                    after = _local_clashes(result, keys, spacing, p, j)
                    if after < before:
                        fixed = True
                        break
                    result[p], result[j] = result[j], result[p]
                if not fixed and scans_left >= 1:
                    # Deterministic fallback: walk the partners in
                    # order and take the first swap that strictly
                    # reduces the local clash count. Same-artist
                    # partners are skipped for the same reason as
                    # above. Each evaluated swap costs one scan
                    # evaluation from the separate scan budget, never
                    # a random-try attempt.
                    for j in range(n):
                        if scans_left < 1:
                            break
                        if j == p or keys[result[j]] == keys[result[p]]:
                            continue
                        scans_left -= 1
                        before = _local_clashes(result, keys, spacing, p, j)
                        result[p], result[j] = result[j], result[p]
                        after = _local_clashes(result, keys, spacing, p, j)
                        if after < before:
                            fixed = True
                            break
                        result[p], result[j] = result[j], result[p]
                if not fixed:
                    bad += 1
        if bad == 0:
            break
        if last_bad >= 0 and bad >= last_bad:
            break
        if attempts_left < 1 and scans_left < 1:
            break
        last_bad = bad
    return result


def shuffle_summary(
    tracks: Sequence,
    spacing: int,
    featuring_is_same_artist: bool = True,
) -> str | None:
    """One-line summary of a shuffle order, for previews only.

    shuffle prints only the first `preview_show` songs, so the first
    page hid whether the full order actually held its artist spacing:
    the repair pass is best effort, and when one artist dominates the
    list clashes remain. This line covers the whole ordered list: its
    size, its distinct artists, how many positions still clash with
    the same artist within `spacing` (the same clash rule
    spread_artists uses), and the most songs by one artist. It
    changes nothing: it only describes an order already computed.
    Tracks with no artist string never clash and do not count toward
    the per-artist max, and when no track names an artist at all the
    max clause is left out too. Artist keys come from
    artist_compare_key, so the case, whitespace, and NFKC fixes
    apply here as well.
    """
    if not tracks:
        return None
    keys = [artist_compare_key(t.artist, featuring_is_same_artist) for t in tracks]
    n = len(tracks)
    identity = list(range(n))
    clashes = sum(
        1 for p in range(n - 1) if _clashes_at(identity, keys, p, spacing)
    )
    distinct = len({key for key in keys if key != ""})
    per_artist: dict[str, int] = {}
    for key in keys:
        if key != "":
            per_artist[key] = per_artist.get(key, 0) + 1
    noun = "song" if n == 1 else "songs"
    artist_noun = "artist" if distinct == 1 else "artists"
    clash_noun = "clash" if clashes == 1 else "clashes"
    parts = [
        f"{n} {noun}",
        f"{distinct} {artist_noun}",
        f"{clashes} same-artist {clash_noun} within spacing {spacing}",
    ]
    if per_artist:
        parts.append(f"max {max(per_artist.values())} by one artist")
    return "Shuffle: " + ", ".join(parts) + "."


def shuffle_tracks(
    tracks: Sequence,
    spacing: int = 2,
    featuring_is_same_artist: bool = True,
    rng: random.Random | None = None,
    size: int | None = None,
    split_collabs: bool = False,
) -> list:
    """Shuffle tracks (Fisher-Yates) and spread artists apart.

    With `size`, only the first `size` shuffled tracks are returned; the
    spacing pass runs on the returned slice, matching the library-shuffle
    size choice in v2.6. The input sequence is never mutated.
    """
    rng = rng or random.Random()
    keys = [
        artist_compare_key(t.artist, featuring_is_same_artist, split_collabs)
        for t in tracks
    ]
    indices = fisher_yates(range(len(tracks)), rng)
    if size is not None:
        indices = indices[: max(0, size)]
    indices = spread_artists(indices, keys, spacing, rng)
    return [tracks[i] for i in indices]
