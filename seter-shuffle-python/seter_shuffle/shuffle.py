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
- It is best effort by design: an artist who makes up most of the list
  cannot be fully separated, and the pass gives up rather than looping
  forever.

Both functions take an explicit random.Random so tests can seed them
and replay an exact order. Passing no rng uses SystemRandom-grade
randomness (random.Random() seeded from the OS).
"""

from __future__ import annotations

import random
from typing import Sequence, TypeVar

from .artists import artist_key

T = TypeVar("T")

_MAX_ATTEMPTS = 20000
_MAX_PASSES = 6
_TRIES_PER_CLASH = 30


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
    """
    rng = rng or random.Random()
    n = len(order)
    if spacing < 1 or n < 2:
        return list(order)
    spacing = min(spacing, n - 1)
    result = list(order)
    attempts_left = _MAX_ATTEMPTS
    last_bad = -1
    for _pass in range(_MAX_PASSES):
        bad = 0
        for p in range(n - 1):
            if _clashes_at(result, keys, p, spacing):
                fixed = False
                for _try in range(_TRIES_PER_CLASH):
                    if attempts_left < 1:
                        break
                    attempts_left -= 1
                    j = rng.randrange(n)
                    if j == p:
                        continue
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
        if attempts_left < 1:
            break
        last_bad = bad
    return result


def shuffle_tracks(
    tracks: Sequence,
    spacing: int = 2,
    featuring_is_same_artist: bool = True,
    rng: random.Random | None = None,
    size: int | None = None,
) -> list:
    """Shuffle tracks (Fisher-Yates) and spread artists apart.

    With `size`, only the first `size` shuffled tracks are returned; the
    spacing pass runs on the returned slice, matching the library-shuffle
    size choice in v2.6. The input sequence is never mutated.
    """
    rng = rng or random.Random()
    keys = [artist_key(t.artist, featuring_is_same_artist) for t in tracks]
    indices = fisher_yates(range(len(tracks)), rng)
    if size is not None:
        indices = indices[: max(0, size)]
    indices = spread_artists(indices, keys, spacing, rng)
    return [tracks[i] for i in indices]
