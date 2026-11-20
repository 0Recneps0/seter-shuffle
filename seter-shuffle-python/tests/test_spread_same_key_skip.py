"""spread_artists skips same-artist swap partners (2026-11-06).

Swapping two songs by the same artist leaves every position's key
unchanged, so the before/after clash check always ties and the swap
is reverted. The old loop still burned one of its 30 tries (and one
of the 20,000 global attempts) on each such partner, which hurts
exactly when one artist dominates the list. The new loop skips a
same-artist partner without counting it as a try, so the 30 tries
go to partners that could actually change the order.
"""

import random
import unittest

from seter_shuffle.shuffle import spread_artists


class ScriptedRandom:
    """randrange stub: a scripted partner sequence, then a fixed fallback."""

    def __init__(self, script, fallback):
        self._script = list(script)
        self._fallback = fallback
        self._i = 0
        self.draws = 0

    def randrange(self, n):
        self.draws += 1
        if self._i < len(self._script):
            j = self._script[self._i]
        else:
            j = self._fallback
        self._i += 1
        return j


def _clash_count(seq, spacing=1):
    count = 0
    for i, key in enumerate(seq):
        for j in range(i + 1, min(i + spacing + 1, len(seq))):
            if seq[j] == key:
                count += 1
    return count


class SameKeySkipTests(unittest.TestCase):
    def test_same_key_draws_do_not_burn_tries(self):
        # Keys A,A,B,B in order, spacing=1. The clash at position 0
        # (A next to A) is only fixed by swapping in a B: swapping
        # position 0 with position 2 drops the local clash count
        # from 2 to 1 (verified by hand). The scripted stream buries
        # that partner behind 30 same-key draws (position 1, also A).
        # The old 30-try loop spent all 30 tries on those no-ops and
        # never reached it; the new loop skips them and fixes the
        # clash in pass 1. The fallback always returns 1, which is
        # either the clashing position itself or a same-artist
        # partner for every later clash, so no later random pass can
        # rescue the old behaviour and mask the difference. The
        # 2026-11-19 scan fallback also fixes the remaining clash at
        # position 1 (swapping it with position 0, the first partner
        # that reduces the local count), so the order now ends
        # clash-free as [1, 2, 0, 3] instead of the old [2, 1, 0, 3],
        # and the run stops after pass 1.
        keys = ["A", "A", "B", "B"]
        rng = ScriptedRandom([1] * 30 + [2], fallback=1)
        order = spread_artists(list(range(4)), keys, spacing=1, rng=rng)
        self.assertEqual(order, [1, 2, 0, 3])
        # 31 draws for the first clash (30 skipped + 1 real) and
        # 300 capped draws for the later clash at position 1 (the
        # scan, not the rng, fixes that one, so there is no pass 2).
        self.assertEqual(rng.draws, 331)

    def test_always_same_key_draws_still_terminate(self):
        # A draw stream that can never produce a useful partner must
        # still return promptly: the per-clash draw cap binds it.
        keys = ["A", "A", "B"]
        rng = ScriptedRandom([], fallback=1)
        order = spread_artists(list(range(3)), keys, spacing=1, rng=rng)
        self.assertEqual(sorted(order), [0, 1, 2])
        # Two passes x 300 capped draws at the unfixable clash.
        self.assertEqual(rng.draws, 600)

    def test_dominant_artist_never_increases_clashes(self):
        # One artist owning most of the list is the case the skip
        # helps most; spreading must still never make it worse and
        # must return every song exactly once.
        keys = ["A"] * 7 + ["B"] * 3
        order = spread_artists(
            list(range(10)), keys, spacing=2, rng=random.Random(7)
        )
        self.assertEqual(sorted(order), list(range(10)))
        self.assertLessEqual(
            _clash_count([keys[i] for i in order], spacing=2),
            _clash_count(keys, spacing=2),
        )


if __name__ == "__main__":
    unittest.main()
