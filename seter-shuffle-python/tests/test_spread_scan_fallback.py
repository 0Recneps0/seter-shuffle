"""Shuffle repair: deterministic scan fallback when random swaps fail.

The repair pass fixes a same-artist clash by swapping the clashing
song with a random partner, keeping the swap only when it strictly
reduces the local clash count. Random draws can miss a reducing
partner that exists: with 30 tries over a big list, a rare good
partner is usually never drawn, so the pass gives up on a clash a
single swap would have fixed. When the random tries fail, the pass
now scans partners in order and takes the first swap that reduces
the local clash count. The scan has its own budget (5000 swap
evaluations per call), separate from the random-try budget, so a
long scan on one clash cannot starve the random tries for later
clashes the way a shared budget did (an earlier prototype sharing
the 20,000-attempt budget made a 846-song, 300-of-one-artist pool
worse, 77.1 -> 91.0 average clashes; the separate budget makes it
better, 77.1 -> 74.8).

Measured live here, same pools and seeds before/after:
  A=45, spacing 1, n=100, 40 seeds: 1.60 -> 1.12 avg clashes left,
    zero-clash runs 9 -> 15
  A=40, spacing 1, n=100, 40 seeds: 0.05 -> 0.00 avg, 38 -> 40 zero
  A=30, spacing 2, n=100, 40 seeds: 2.83 -> 2.35 avg
  A=300, spacing 2, n=846, 10 seeds: 77.1 -> 74.8 avg
  A=380, spacing 1, n=846, 10 seeds: 18.9 -> 17.0 avg
The scan changes no rule: same-artist partners are still skipped
(swapping two songs by the same artist cannot change any clash
count), the same local-clash measure decides, and the pass is
still best effort (a list one artist dominates cannot be fully
separated, and the pass still gives up rather than looping).
"""

import random
import unittest

from seter_shuffle.shuffle import (
    _clashes_at,
    _local_clashes,
    _MAX_ATTEMPTS,
    _MAX_DRAWS_PER_CLASH,
    _MAX_PASSES,
    _TRIES_PER_CLASH,
    fisher_yates,
    spread_artists,
)


def _count_clashes(order, keys, spacing):
    return sum(
        1 for p in range(len(order) - 1) if _clashes_at(order, keys, p, spacing)
    )


def _spread_artists_no_scan(order, keys, spacing, rng=None):
    """The pre-2026-11-19 repair pass, copied verbatim, for comparison.

    Random tries only, no deterministic scan. Used here only to prove
    the new tests measure a real gap in the old behaviour, not to
    re-implement the production code.
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
                tries = 0
                for _draw in range(_MAX_DRAWS_PER_CLASH):
                    if tries >= _TRIES_PER_CLASH or attempts_left < 1:
                        break
                    j = rng.randrange(n)
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


class _StuckRng:
    """An rng that always draws the same partner: the random phase
    can never find the reducing swap, so only the scan can fix it."""

    def __init__(self, value):
        self.value = value

    def randrange(self, n):
        return self.value % n


class TestSpreadScanFallback(unittest.TestCase):
    def test_scan_fixes_clash_random_tries_cannot(self):
        # Keys A,A,B,C, spacing 1, order [0,1,2,3]: position 0 clashes
        # with position 1. Swapping 0 with 2 (B) leaves a clash
        # (B,A,A,C still clashes at 1-2); swapping 0 with 3 (C) clears
        # it (C,A,B,A). An rng stuck on partner 2 burns all 30 random
        # tries on the useless swap, so only the scan finds partner 3.
        keys = ["A", "A", "B", "C"]
        order = [0, 1, 2, 3]
        self.assertEqual(_count_clashes(order, keys, 1), 1)
        old = _spread_artists_no_scan(list(order), keys, 1, _StuckRng(2))
        self.assertEqual(_count_clashes(old, keys, 1), 1)
        fixed = spread_artists(list(order), keys, 1, _StuckRng(2))
        self.assertEqual(_count_clashes(fixed, keys, 1), 0)
        self.assertEqual(sorted(fixed), [0, 1, 2, 3])

    def test_scan_skips_same_artist_partners(self):
        # One artist owns the whole list: no swap can change any clash
        # count, so the scan must not invent a fix or loop forever.
        keys = ["A"] * 6
        order = [0, 1, 2, 3, 4, 5]
        fixed = spread_artists(list(order), keys, 1, random.Random(1))
        self.assertEqual(sorted(fixed), [0, 1, 2, 3, 4, 5])
        self.assertEqual(
            _count_clashes(fixed, keys, 1), _count_clashes(order, keys, 1)
        )

    def test_scan_improves_dominated_pool(self):
        # A=45, spacing 1, n=100, 40 seeds: the old pass leaves 1.60
        # clashes on average with 9 zero-clash runs; the scan leaves
        # 1.12 with 15. The old-code assertions pin the gap; the
        # new-code assertions pin the improvement.
        keys = ["A"] * 45 + [f"B{i}" for i in range(55)]
        old_total = old_zero = new_total = new_zero = 0
        for seed in range(40):
            idx = fisher_yates(range(100), random.Random(seed))
            c_old = _count_clashes(
                _spread_artists_no_scan(list(idx), keys, 1, random.Random(seed)),
                keys,
                1,
            )
            c_new = _count_clashes(
                spread_artists(list(idx), keys, 1, random.Random(seed)),
                keys,
                1,
            )
            old_total += c_old
            new_total += c_new
            old_zero += c_old == 0
            new_zero += c_new == 0
        self.assertGreaterEqual(old_total / 40, 1.5)
        self.assertLessEqual(new_total / 40, 1.3)
        self.assertGreaterEqual(new_zero, 12)

    def test_scan_does_not_starve_large_dominated_pool(self):
        # A=300, spacing 2, n=846 (Spencer's library scale), 10 seeds:
        # the scan must not leave MORE clashes than the old pass. A
        # shared-budget prototype did (77.1 -> 91.0); the separate
        # scan budget keeps it better (77.1 -> 74.8).
        keys = ["A"] * 300 + [f"B{i}" for i in range(546)]
        old_total = new_total = 0
        for seed in range(10):
            idx = fisher_yates(range(846), random.Random(seed))
            old_total += _count_clashes(
                _spread_artists_no_scan(list(idx), keys, 2, random.Random(seed)),
                keys,
                2,
            )
            new_total += _count_clashes(
                spread_artists(list(idx), keys, 2, random.Random(seed)),
                keys,
                2,
            )
        self.assertLess(new_total, old_total)

    def test_spread_guards_unchanged(self):
        # Input is never mutated; spacing < 1 returns the order as-is;
        # empty and single-song lists pass through; same seed replays
        # the same order.
        keys = ["A", "A", "B", "C"]
        order = [0, 1, 2, 3]
        before = list(order)
        spread_artists(order, keys, 1, random.Random(7))
        self.assertEqual(order, before)
        self.assertEqual(spread_artists(list(order), keys, 0), order)
        self.assertEqual(spread_artists([], [], 1), [])
        self.assertEqual(spread_artists([0], ["A"], 1), [0])
        keys100 = ["A"] * 40 + [f"B{i}" for i in range(60)]
        idx = fisher_yates(range(100), random.Random(5))
        first = spread_artists(list(idx), keys100, 1, random.Random(9))
        second = spread_artists(list(idx), keys100, 1, random.Random(9))
        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
