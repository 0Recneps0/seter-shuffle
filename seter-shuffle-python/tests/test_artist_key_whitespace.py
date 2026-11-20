"""Artist keys ignore leading/trailing whitespace (2026-11-11 experimental).

Rips and taggers leave stray spaces in artist metadata, and the
2026-11-03 case fix did not cover them: "Drake" and "Drake " (or
" Drake") produced different keys, so they counted as different
artists and defeated spacing in shuffle, Flow, and Rediscover's
max-per-artist count. Worse, the featuring truncation only stripped
the tail, so " Drake feat. X" kept its leading space even after the
marker was cut. A whitespace-only artist string ("   ") also
returned a non-empty key, so it counted as a real artist instead of
never clashing like "" and None do. All four paths go through
artist_key, so stripping the key fixes all of them at once; the key
is never displayed, so no output text changes.
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


class ArtistKeyWhitespaceTests(unittest.TestCase):
    def test_trailing_space_is_one_key(self):
        self.assertEqual(artist_key("Drake "), "drake")
        self.assertEqual(artist_key("Drake  "), artist_key("Drake"))

    def test_leading_space_is_one_key(self):
        self.assertEqual(artist_key(" Drake"), "drake")
        self.assertEqual(artist_key("  Drake"), artist_key("Drake"))

    def test_featuring_truncation_strips_leading_space_too(self):
        self.assertEqual(artist_key(" Drake feat. X"), "drake")
        self.assertEqual(artist_key("Drake feat. X "), "drake")

    def test_featuring_off_strips_too(self):
        self.assertEqual(
            artist_key("Drake ", featuring_is_same_artist=False), "drake"
        )
        self.assertEqual(
            artist_key(" Drake", featuring_is_same_artist=False), "drake"
        )

    def test_whitespace_only_is_empty(self):
        self.assertEqual(artist_key("   "), "")
        self.assertEqual(artist_key("\t"), "")
        self.assertEqual(artist_key(" \t "), "")

    def test_empty_and_none_still_empty(self):
        self.assertEqual(artist_key(""), "")
        self.assertEqual(artist_key(None), "")

    def test_shuffle_separates_whitespace_variants(self):
        # Three tracks by the same artist spelled with stray spaces,
        # plus nine distinct artists: spacing=2 needs 2 other songs
        # between repeats, which the fillers make possible.
        artists = ["Drake", "Drake ", " Drake"] + [f"Filler{i}" for i in range(9)]
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
                f"seed {seed}: whitespace-variant Drake tracks too close: {positions}",
            )

    def test_flow_order_separates_whitespace_variants(self):
        # Greedy Flow walk: the 1000 spacing penalty must fire for a
        # whitespace-variant repeat, not just an exact-string repeat.
        energies = [50, 60, 70, 80, 55, 65]
        groups = [2, 2, 2, 2, 2, 2]
        years = [2020] * 6
        artist_keys = [artist_key(a) for a in
                       ["Drake", "Other1", "Drake ", "Other2", "Other3", "Other4"]]
        order = flow_order(energies, groups, years, artist_keys,
                           total=6, spacing=2)
        positions = [p for p, i in enumerate(order) if artist_keys[i] == "drake"]
        self.assertEqual(len(positions), 2)
        self.assertGreater(_min_gap(positions), 2)


if __name__ == "__main__":
    unittest.main()
