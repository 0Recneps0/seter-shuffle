"""Shuffle full-list summary (2026-11-12 experimental).

shuffle prints only the first preview_show songs, so the first page
hid whether the full order actually held its artist spacing: the
repair pass is best effort, and when one artist dominates the list
clashes remain. The new summary line covers the whole ordered list.
Preview only: it changes no order, no file, and no playlist.
"""

from __future__ import annotations

import io
import random
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.cli import main
from seter_shuffle.shuffle import shuffle_summary, shuffle_tracks
from seter_shuffle.tracks import Track, track_from_dict

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "sample-library.json"


def _track(pid: str, artist: str) -> Track:
    return track_from_dict(
        {
            "persistent_id": pid,
            "name": f"Song {pid}",
            "artist": artist,
            "played_count": 0,
        }
    )


class TestShuffleSummary(unittest.TestCase):
    def test_empty_returns_none(self):
        self.assertIsNone(shuffle_summary([], 2))

    def test_no_clashes_well_spread(self):
        tracks = [_track(p, a) for p, a in zip("ABCD", ["A", "B", "C", "D"])]
        self.assertEqual(
            shuffle_summary(tracks, 2),
            "Shuffle: 4 songs, 4 artists, 0 same-artist clashes "
            "within spacing 2, max 1 by one artist.",
        )

    def test_back_to_back_counts_one_clash_position(self):
        tracks = [_track(p, a) for p, a in zip("ABC", ["A", "A", "B"])]
        self.assertEqual(
            shuffle_summary(tracks, 2),
            "Shuffle: 3 songs, 2 artists, 1 same-artist clash "
            "within spacing 2, max 2 by one artist.",
        )

    def test_clash_within_spacing_two_not_beyond(self):
        tracks = [_track(p, a) for p, a in zip("ABCD", ["A", "B", "A", "C"])]
        self.assertIn("1 same-artist clash within spacing 2", shuffle_summary(tracks, 2))
        self.assertIn("0 same-artist clashes within spacing 1", shuffle_summary(tracks, 1))

    def test_three_in_a_row_counts_two_positions(self):
        tracks = [_track(p, a) for p, a in zip("ABC", ["A", "A", "A"])]
        self.assertIn("2 same-artist clashes within spacing 2", shuffle_summary(tracks, 2))

    def test_empty_artist_never_clashes_and_no_max_clause(self):
        tracks = [_track(p, "") for p in "ABC"]
        self.assertEqual(
            shuffle_summary(tracks, 2),
            "Shuffle: 3 songs, 0 artists, 0 same-artist clashes within spacing 2.",
        )

    def test_max_per_artist(self):
        tracks = [_track(p, a) for p, a in zip("ABCDE", ["A", "B", "A", "C", "A"])]
        summary = shuffle_summary(tracks, 2)
        self.assertIn("max 3 by one artist", summary)
        self.assertIn("2 same-artist clashes within spacing 2", summary)

    def test_singular_forms(self):
        tracks = [_track("A", "Solo")]
        self.assertEqual(
            shuffle_summary(tracks, 2),
            "Shuffle: 1 song, 1 artist, 0 same-artist clashes "
            "within spacing 2, max 1 by one artist.",
        )

    def test_case_insensitive_keys_count_as_one_artist(self):
        tracks = [_track(p, a) for p, a in zip("AB", ["Drake", "drake"])]
        summary = shuffle_summary(tracks, 2)
        self.assertIn("1 artist", summary)
        self.assertIn("max 2 by one artist", summary)
        self.assertIn("1 same-artist clash within spacing 2", summary)

    def test_whitespace_variant_keys_count_as_one_artist(self):
        tracks = [_track(p, a) for p, a in zip("AB", ["Drake", "Drake "])]
        summary = shuffle_summary(tracks, 2)
        self.assertIn("1 artist", summary)
        self.assertIn("max 2 by one artist", summary)

    def test_summary_does_not_change_the_order(self):
        tracks = [_track(p, a) for p, a in zip("ABCD", ["A", "B", "A", "C"])]
        before = list(tracks)
        shuffle_summary(tracks, 2)
        self.assertEqual(tracks, before)

    def test_shuffle_tracks_end_to_end_no_clashes(self):
        artists = [f"Artist {i}" for i in range(10)]
        tracks = [
            _track(f"{i}-{j}", artist)
            for i, artist in enumerate(artists)
            for j in range(2)
        ]
        for seed in range(10):
            ordered = shuffle_tracks(tracks, spacing=2, rng=random.Random(seed))
            summary = shuffle_summary(ordered, 2)
            self.assertIn("0 same-artist clashes within spacing 2", summary)
            self.assertIn("10 artists", summary)

    def test_cli_shuffle_prints_summary_line(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = main(["shuffle", "--library", str(FIXTURE), "--seed", "1"])
        self.assertEqual(code, 0)
        out = buf.getvalue()
        self.assertIn("Shuffle: ", out)
        self.assertRegex(
            out,
            r"Shuffle: \d+ songs?, \d+ artists?, \d+ same-artist clash",
        )

    def test_cli_shuffle_quiet_suppresses_summary(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = main(
                ["shuffle", "--library", str(FIXTURE), "--seed", "1", "--quiet"]
            )
        self.assertEqual(code, 0)
        self.assertEqual(buf.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
