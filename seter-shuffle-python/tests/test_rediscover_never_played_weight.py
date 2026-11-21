"""Rediscover's never-played base weight: unplayed starts at the played-song base (2026-11-18 experimental).

A never-played song added long ago is the most forgotten song possible,
but the old 0.4 base capped it at 2.0 against a 10-play song's 30.0, a
15:1 ratio no amount of forgottenness could close: in an even 50/50
pool never-played songs took 47 of 600 picks (7.8%) over 20 seeds. The
base is now 1.0, the same base every played song starts from, so the
plays tier (not a 60% unplayed discount) is what separates played from
unplayed: a never-played song tops out at 5.0, still below a
once-played song's 7.5 at the same forgottenness. No eligibility,
history, cap, or ordering rule changes.
"""

import random
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.rediscover import pick_rediscover, rediscover_weight
from seter_shuffle.settings import Settings
from seter_shuffle.tracks import Track

NOW = datetime(2026, 10, 28, tzinfo=timezone.utc)
LONG_AGO = NOW - timedelta(days=1095)


def _track(pid: str, plays: int, **overrides) -> Track:
    base = {
        "persistent_id": pid,
        "name": f"Song {pid}",
        "artist": f"Artist {pid}",
        "genre": "Pop",
        "bpm": 120,
        "year": 2020,
        "played_count": plays,
        "played_date": LONG_AGO if plays > 0 else None,
        "date_added": LONG_AGO,
    }
    base.update(overrides)
    return Track(**base)


def _settings(target: int = 30) -> Settings:
    # Target exactly `target` for a 100-track pool: 100% of the
    # library, clamped to the same min and max.
    return Settings(
        rediscover_percent=100,
        rediscover_min=target,
        rediscover_max=target,
    )


def _pool(never: int, plays: int) -> list[Track]:
    tracks = [_track(f"NP{i:03d}", 0) for i in range(never)]
    tracks += [_track(f"P{i:03d}", plays) for i in range(50)]
    return tracks


def _never_played_share(pool: list[Track], seeds: range = range(20)) -> int:
    total = 0
    for seed in seeds:
        picks, _candidates, _target = pick_rediscover(
            pool, NOW, _settings(), rng=random.Random(seed)
        )
        total += sum(1 for t in picks if t.played_count == 0)
    return total


class NeverPlayedWeightTests(unittest.TestCase):
    def test_never_played_weight_is_base_times_forgotten(self):
        # 1.0 base x forgotten multiplier capped at 5 (was 0.4 x 5 = 2.0).
        self.assertAlmostEqual(
            rediscover_weight(_track("n", 0), NOW, Settings()), 1.0 * 5
        )

    def test_never_played_below_once_played_same_forgottenness(self):
        # The unplayed discount survives as a smaller gap: 5.0 vs 7.5,
        # not 2.0 vs 7.5. Played songs still win at equal forgottenness.
        never = rediscover_weight(_track("n", 0), NOW, Settings())
        once = rediscover_weight(_track("o", 1), NOW, Settings())
        self.assertAlmostEqual(never, 5.0)
        self.assertAlmostEqual(once, 1.5 * 5)
        self.assertLess(never, once)

    def test_never_played_boosts_still_apply(self):
        # Favorited and 4-5-star boosts multiply the new base exactly
        # as they multiplied the old one; only the base changed.
        fav = _track("f", 0, favorited=True)
        self.assertAlmostEqual(rediscover_weight(fav, NOW, Settings()), 1.0 * 3 * 5)
        rated = _track("r", 0, rating=100)
        self.assertAlmostEqual(rediscover_weight(rated, NOW, Settings()), 1.0 * 2 * 5)

    def test_never_played_skips_still_divide(self):
        # Two skips are not skip-heavy, so the song stays eligible
        # and the skips divide the new base: 1.0 / 3 x 5.
        skipped = _track("s", 0, skipped_count=2)
        self.assertAlmostEqual(
            rediscover_weight(skipped, NOW, Settings()), 1.0 / 3 * 5
        )

    def test_never_played_recently_added_still_zero(self):
        # Eligibility is untouched: a never-played song added within
        # the stale window is still ineligible, weight 0.0.
        recent = _track("r", 0, date_added=NOW - timedelta(days=10))
        self.assertEqual(rediscover_weight(recent, NOW, Settings()), 0.0)

    def test_even_pool_share_vs_ten_play_songs(self):
        # 50 never-played vs 50 played-10, all equally forgotten, 20
        # seeds, 30 picks each: expected share 250/1750 = 14.3%
        # (~86 of 600). The old 0.4 base took 47 of 600 (7.8%).
        total = _never_played_share(_pool(50, 10))
        self.assertGreaterEqual(total, 60)
        self.assertLessEqual(total, 115)

    def test_even_pool_share_vs_once_played_songs(self):
        # 50 never-played vs 50 played-once, all equally forgotten:
        # expected share 250/625 = 40% (~240 of 600). The old 0.4
        # base took ~126 of 600 (21%).
        total = _never_played_share(_pool(50, 1))
        self.assertGreaterEqual(total, 200)
        self.assertLessEqual(total, 280)

    def test_all_never_played_pool_still_fills(self):
        # Guard: a pool of only never-played songs still fills the
        # target exactly as before; the change is a weight, not a
        # new eligibility or fill rule.
        pool = [_track(f"NP{i:03d}", 0) for i in range(100)]
        picks, candidates, target = pick_rediscover(
            pool, NOW, _settings(), rng=random.Random(3)
        )
        self.assertEqual(target, 30)
        self.assertEqual(len(picks), 30)
        self.assertEqual(candidates, 100)
        self.assertTrue(all(t.played_count == 0 for t in picks))


if __name__ == "__main__":
    unittest.main()
