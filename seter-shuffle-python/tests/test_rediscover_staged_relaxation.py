"""Rediscover relaxes its variety rules one at a time (2026-11-04 experimental).

Before this change, a pool too small to fill the target under both
rules fell straight to a pass enforcing neither rule, so a slot could
be filled by a song picked within the cooldown window even when an
extra song by an already-picked artist would have filled it, or by a
second song from one artist even when a cooldown repeat would have.
Now the passes run in stages: both rules, cooldown only, artist cap
only, neither, then the weight-ordered fill. Cooldown is relaxed last
but one because not repeating recent Rediscover picks is the point
of the playlist; the artist cap is relaxed before it, and both are
relaxed only when neither single relaxation can fill the target.
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


def make_track(pid: str, artist: str, name: str) -> Track:
    return Track(
        persistent_id=pid,
        name=name,
        artist=artist,
        genre="Pop",
        bpm=120,
        year=2020,
        played_count=5,
        played_date=datetime(2024, 1, 1, tzinfo=timezone.utc),
        date_added=datetime(2020, 1, 1, tzinfo=timezone.utc),
    )


def settings_for(target: int) -> Settings:
    return Settings(
        rediscover_percent=100,
        rediscover_min=target,
        rediscover_max=target,
        rediscover_max_per_artist=1,
    )


class RediscoverStagedRelaxationTests(unittest.TestCase):
    def test_cap_relaxes_before_cooldown_repeats(self):
        # Two songs by artist A (neither in history) and one song by
        # artist B that IS in history, cap 1, target 2. Pass 1 picks
        # one A song; the old single relaxed pass could then fill
        # the slot with the history song. The staged passes must
        # fill it with the second A song instead, on every seed.
        tracks = [
            make_track("a1", "A", "Song A1"),
            make_track("a2", "A", "Song A2"),
            make_track("b1", "B", "Song B1"),
        ]
        for seed in range(20):
            picked, _candidates, target = pick_rediscover(
                tracks, NOW, settings_for(2),
                history_ids={"b1"}, rng=random.Random(seed),
            )
            self.assertEqual(target, 2)
            self.assertEqual(
                {t.persistent_id for t in picked}, {"a1", "a2"},
                f"seed {seed} repeated a cooldown song instead of "
                "relaxing the artist cap",
            )

    def test_cooldown_relaxes_before_cap_breaks_twice(self):
        # One fresh song by artist A and two history songs by artist
        # B, cap 1, target 2. Pass 1 picks A only, the cooldown-only
        # pass cannot fill, so the cap-only pass must fill with
        # exactly one B song, never both B songs, on every seed.
        tracks = [
            make_track("a1", "A", "Song A1"),
            make_track("b1", "B", "Song B1"),
            make_track("b2", "B", "Song B2"),
        ]
        for seed in range(20):
            picked, _candidates, target = pick_rediscover(
                tracks, NOW, settings_for(2),
                history_ids={"b1", "b2"}, rng=random.Random(seed),
            )
            ids = {t.persistent_id for t in picked}
            self.assertEqual(target, 2)
            self.assertEqual(len(ids), 2)
            self.assertIn("a1", ids)
            self.assertEqual(len(ids & {"b1", "b2"}), 1,
                             f"seed {seed} picked both songs by one artist")

    def test_both_relax_only_as_last_resort(self):
        # One fresh song by artist A and two history songs by artist
        # B, cap 1, target 3: neither single relaxation can fill the
        # playlist, so the final neither-rules pass must take all
        # three rather than leaving the playlist short.
        tracks = [
            make_track("a1", "A", "Song A1"),
            make_track("b1", "B", "Song B1"),
            make_track("b2", "B", "Song B2"),
        ]
        for seed in range(10):
            picked, _candidates, target = pick_rediscover(
                tracks, NOW, settings_for(3),
                history_ids={"b1", "b2"}, rng=random.Random(seed),
            )
            self.assertEqual(target, 3)
            self.assertEqual(
                {t.persistent_id for t in picked}, {"a1", "b1", "b2"},
                f"seed {seed} left the playlist short",
            )

    def test_strict_pool_still_respects_both_rules(self):
        # Regression guard: when the pool CAN fill under both rules,
        # no relaxation pass runs at all, so the cap and the cooldown
        # both hold exactly as before.
        tracks = []
        for artist in ("A", "B", "C", "D"):
            for i in range(3):
                tracks.append(make_track(f"{artist.lower()}{i}", artist, f"Song {artist}{i}"))
        picked, _candidates, target = pick_rediscover(
            tracks, NOW, settings_for(4),
            history_ids={"a0"}, rng=random.Random(7),
        )
        self.assertEqual(target, 4)
        self.assertEqual(len(picked), 4)
        self.assertNotIn("a0", [t.persistent_id for t in picked])
        artists = [t.artist for t in picked]
        self.assertEqual(len(set(artists)), 4)


if __name__ == "__main__":
    unittest.main()
