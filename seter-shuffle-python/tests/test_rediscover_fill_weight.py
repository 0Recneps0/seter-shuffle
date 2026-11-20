"""Rediscover's last-resort fill takes the highest-weight songs left (2026-11-16 experimental).

When the four staged sampling passes cannot fill the target, the fill
used to take the front of the candidate list in library order, so a
slot could go to a weak song that happened to sit early in the dump
while a stronger song sat later. The fill now takes the highest-weight
unpicked candidates; ties keep library order, so an equal-weight pool
fills exactly as before. The sampling passes themselves are untouched.
"""

import random
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.rediscover import pick_rediscover
from seter_shuffle.settings import Settings
from seter_shuffle.tracks import Track

NOW = datetime(2026, 10, 28, tzinfo=timezone.utc)
OLD = datetime(2021, 1, 1, tzinfo=timezone.utc)
ADDED = datetime(2020, 1, 1, tzinfo=timezone.utc)


class ZeroRandom(random.Random):
    """Every sampling draw lands on candidate 0.

    The staged passes can then only ever pick the first candidate, so
    the fill has to supply every remaining slot. The final shuffle and
    artist-spread use randrange, not random(), so they still vary the
    order without changing which songs are picked.
    """

    def random(self):
        return 0.0


def weighted_track(pid: str, plays: int, rating: int = 0, favorited: bool = False) -> Track:
    return Track(
        persistent_id=pid,
        name=f"Song {pid}",
        artist=f"Artist {pid}",
        genre="Pop",
        bpm=120,
        year=2020,
        played_count=plays,
        played_date=OLD if plays > 0 else None,
        date_added=ADDED,
        rating=rating,
        favorited=favorited,
    )


def settings_for(target: int) -> Settings:
    return Settings(
        rediscover_percent=100,
        rediscover_min=target,
        rediscover_max=target,
        rediscover_max_per_artist=10,
    )


class RediscoverFillWeightTests(unittest.TestCase):
    def test_fill_takes_highest_weight_remaining(self):
        # Library order is m1 (2.0), whale (180), m2 (7.5), m3 (10),
        # m4 (15), m5 (20): weights rise with library position, so a
        # library-order fill takes the weakest remaining songs. Only
        # m1 is sampled; the fill must supply four more, and the
        # strongest four left are whale, m5, m4, m3, not m2.
        tracks = [
            weighted_track("m1", 0),
            weighted_track("whale", 10, 100, True),
            weighted_track("m2", 1),
            weighted_track("m3", 2),
            weighted_track("m4", 4),
            weighted_track("m5", 6),
        ]
        picked, _candidates, target = pick_rediscover(
            tracks, NOW, settings_for(5), history_ids=set(), rng=ZeroRandom(0)
        )
        self.assertEqual(target, 5)
        self.assertEqual(len(picked), 5)
        self.assertEqual(len({t.persistent_id for t in picked}), 5)
        self.assertEqual(
            {t.persistent_id for t in picked},
            {"m1", "m3", "m4", "m5", "whale"},
        )

    def test_fill_single_slot_takes_heaviest(self):
        # Same point with one slot to fill: library order is A (2.0,
        # sampled), B (7.5), C (20); the one fill slot goes to C.
        tracks = [
            weighted_track("a", 0),
            weighted_track("b", 1),
            weighted_track("c", 6),
        ]
        picked, _candidates, target = pick_rediscover(
            tracks, NOW, settings_for(2), history_ids=set(), rng=ZeroRandom(0)
        )
        self.assertEqual(target, 2)
        self.assertEqual({t.persistent_id for t in picked}, {"a", "c"})

    def test_fill_keeps_library_order_on_weight_ties(self):
        # Equal weights: the weight sort ties, so the fill keeps
        # library order exactly as before. Guards the staged-relaxation
        # pools, where every track weighs the same.
        tracks = [
            Track(
                persistent_id=f"t{i}",
                name=f"Song {i}",
                artist=f"Artist {i}",
                genre="Pop",
                bpm=120,
                year=2020,
                played_count=5,
                played_date=datetime(2024, 1, 1, tzinfo=timezone.utc),
                date_added=ADDED,
            )
            for i in range(5)
        ]
        picked, _candidates, target = pick_rediscover(
            tracks, NOW, settings_for(3), history_ids=set(), rng=ZeroRandom(0)
        )
        self.assertEqual(target, 3)
        self.assertEqual(
            {t.persistent_id for t in picked}, {"t0", "t1", "t2"},
        )

    def test_sampling_path_unchanged_when_pool_fills(self):
        # Regression guard: when the pool fills under both rules, the
        # fill never runs, so the cap and the cooldown hold exactly
        # as before across seeds.
        tracks = []
        for artist in ("A", "B", "C", "D", "E", "F"):
            for i in range(3):
                tracks.append(
                    Track(
                        persistent_id=f"{artist.lower()}{i}",
                        name=f"Song {artist}{i}",
                        artist=artist,
                        genre="Pop",
                        bpm=120,
                        year=2020,
                        played_count=5,
                        played_date=datetime(2024, 1, 1, tzinfo=timezone.utc),
                        date_added=ADDED,
                    )
                )
        settings = Settings(
            rediscover_percent=100,
            rediscover_min=6,
            rediscover_max=6,
            rediscover_max_per_artist=1,
        )
        for seed in range(10):
            picked, _candidates, target = pick_rediscover(
                tracks, NOW, settings,
                history_ids={"a0", "b0"}, rng=random.Random(seed),
            )
            self.assertEqual(target, 6)
            self.assertEqual(len(picked), 6)
            ids = [t.persistent_id for t in picked]
            self.assertNotIn("a0", ids)
            self.assertNotIn("b0", ids)
            artists = [t.artist for t in picked]
            self.assertEqual(len(set(artists)), 6)


if __name__ == "__main__":
    unittest.main()
