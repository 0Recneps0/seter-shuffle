"""Artist keys are case-insensitive (2026-11-03 experimental).

The module docstring always claimed case-insensitive matching (the
AppleScript behaviour), but the Python port compared keys with ==,
so "Drake" and "drake" from different rips counted as different
artists and defeated spacing in shuffle, Flow, and Rediscover's
max-per-artist count. All three paths go through artist_key, so
lowercasing the key fixes all three at once; the key is never
displayed, so no output text changes.
"""

import random
import unittest

from seter_shuffle.artists import artist_key
from seter_shuffle.flow import flow_order
from seter_shuffle.shuffle import shuffle_tracks
from seter_shuffle.tracks import Track


def _min_gap(positions: list[int]) -> int:
    """Smallest distance between any two positions (0 if < 2)."""
    if len(positions) < 2:
        return 0
    ordered = sorted(positions)
    return min(b - a for a, b in zip(ordered, ordered[1:]))


class ArtistKeyCaseTests(unittest.TestCase):
    def test_same_artist_different_case_is_one_key(self):
        self.assertEqual(artist_key("Drake"), artist_key("drake"))
        self.assertEqual(artist_key("Drake"), artist_key("DRAKE"))
        self.assertEqual(artist_key("Drake"), "drake")

    def test_featuring_markers_still_case_insensitive(self):
        self.assertEqual(artist_key("Drake FEAT. Luna"), "drake")
        self.assertEqual(artist_key("DRAKE (FT. Luna)"), "drake")

    def test_featuring_off_still_lowercases(self):
        self.assertEqual(
            artist_key("Drake feat. Luna", featuring_is_same_artist=False),
            "drake feat. luna",
        )

    def test_empty_and_none_still_empty(self):
        self.assertEqual(artist_key(""), "")
        self.assertEqual(artist_key(None), "")

    def test_shuffle_separates_case_variants(self):
        # Three tracks by the same artist spelled three ways, plus
        # nine distinct artists: spacing=2 needs 2 other songs
        # between repeats, which the fillers make possible.
        artists = ["Drake", "drake", "DRAKE"] + [f"Filler{i}" for i in range(9)]
        tracks = [
            Track(persistent_id=str(i), name=f"Song{i}", artist=a)
            for i, a in enumerate(artists)
        ]
        for seed in range(20):
            ordered = shuffle_tracks(tracks, spacing=2, rng=random.Random(seed))
            positions = [
                p for p, t in enumerate(ordered)
                if artist_key(t.artist) == "drake"
            ]
            self.assertEqual(len(positions), 3)
            self.assertGreater(
                _min_gap(positions), 2,
                f"seed {seed}: case-variant Drake tracks too close: {positions}",
            )

    def test_flow_order_separates_case_variants(self):
        # Greedy Flow walk: the 1000 spacing penalty must fire for a
        # case-variant repeat, not just an exact-string repeat.
        energies = [50, 60, 70, 80, 55, 65]
        groups = [2, 2, 2, 2, 2, 2]
        years = [2020] * 6
        artist_keys = [artist_key(a) for a in
                       ["Drake", "Other1", "drake", "Other2", "Other3", "Other4"]]
        order = flow_order(energies, groups, years, artist_keys,
                           total=6, spacing=2)
        positions = [p for p, i in enumerate(order) if artist_keys[i] == "drake"]
        self.assertEqual(len(positions), 2)
        self.assertGreater(_min_gap(positions), 2)


if __name__ == "__main__":
    unittest.main()
