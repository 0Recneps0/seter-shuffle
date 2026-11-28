"""Tests for Flow album spacing (2026-11-27 experimental).

Artist spacing cannot see albums: a soundtrack or compilation has a
different artist on nearly every track, so the walk could play three
songs from the same album in a row (same genre, era, and energy, so
they cluster even though no artist repeats). A track whose album
appeared within the last `spacing` picks now costs the same 1000 as
a repeated artist.

No test here touches Music or the network. Standard library only.
"""

from __future__ import annotations

import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.flow import album_key, flow_order, prepare_flow
from seter_shuffle.settings import Settings
from seter_shuffle.tracks import Track

GROUPS = [3, 3, 3, 3, 3]
YEARS: list[int | None] = [None, None, None, None, None]
ENERGIES = [50, 50, 50, 50, 50]
FAMS = [0, 0, 0, 0, 0]


def _distance(order: list[int], a: int, b: int) -> int:
    """Positions apart in `order` (1 = adjacent)."""
    return abs(order.index(a) - order.index(b))


class AlbumKeyTest(unittest.TestCase):
    def test_case_and_whitespace_fold(self):
        self.assertEqual(album_key("Greatest Hits"), album_key("greatest  hits "))
        self.assertEqual(album_key("  Abbey Road "), album_key("abbey road"))

    def test_blank_never_counts(self):
        self.assertEqual(album_key(""), "")
        self.assertEqual(album_key("   "), "")
        self.assertEqual(album_key(None), "")


class AlbumSpacingTest(unittest.TestCase):
    def test_same_album_different_artists_separated(self):
        # Two soundtrack songs (different artists) plus three fillers,
        # all flat energy so only spacing moves the walk. Without the
        # rule the walk returns library order and the pair is adjacent.
        keys = ["a", "b", "c", "d", "e"]
        albums = ["Soundtrack", "Soundtrack", "Other", "Other 2", "Other 3"]
        without = flow_order(ENERGIES, GROUPS, YEARS, keys, 5, spacing=2)
        self.assertEqual(_distance(without, 0, 1), 1)
        with_albums = flow_order(
            ENERGIES, GROUPS, YEARS, keys, 5, spacing=2, album_keys=albums
        )
        # Spacing 2 keeps the pair 2 picks apart: the second
        # soundtrack song is free again at the fourth slot.
        self.assertEqual(with_albums, [0, 2, 3, 1, 4])
        self.assertGreaterEqual(_distance(with_albums, 0, 1), 3)

    def test_single_album_pool_is_best_effort(self):
        # Every song shares the album: the penalty is uniform, so the
        # ranking is unchanged and no song is dropped.
        keys = ["a", "b", "c", "d"]
        albums = ["One Album"] * 4
        order = flow_order(
            [50, 50, 50, 50], [3, 3, 3, 3], [None] * 4, keys, 4,
            spacing=2, album_keys=albums,
        )
        self.assertEqual(sorted(order), [0, 1, 2, 3])

    def test_blank_albums_never_spaced(self):
        # Two untagged tracks (no album) may sit next to each other.
        keys = ["a", "b", "c"]
        albums = ["", "", "Other"]
        order = flow_order(
            [50, 50, 50], [3, 3, 3], [None] * 3, keys, 3,
            spacing=2, album_keys=albums,
        )
        self.assertEqual(order, [0, 1, 2])

    def test_artist_spacing_still_holds_with_albums(self):
        # Same artist on different albums is still spaced by the
        # artist rule, even with album keys supplied.
        keys = ["a", "a", "b"]
        albums = ["First", "Second", "Third"]
        order = flow_order(
            [50, 50, 50], [3, 3, 3], [None] * 3, keys, 3,
            spacing=2, album_keys=albums,
        )
        self.assertEqual(order, [0, 2, 1])
        self.assertGreaterEqual(_distance(order, 0, 1), 2)

    def test_spacing_one_is_back_to_back_only(self):
        # With spacing=1 the album must not repeat on the very next
        # pick, but may return two picks later.
        keys = ["a", "b", "c"]
        albums = ["Shared", "Shared", "Other"]
        order = flow_order(
            [50, 50, 50], [3, 3, 3], [None] * 3, keys, 3,
            spacing=1, album_keys=albums,
        )
        self.assertEqual(order, [0, 2, 1])

    def test_no_album_keys_behaves_as_before(self):
        # The parameter defaults to off, so old callers are unchanged.
        keys = ["a", "b", "c", "d", "e"]
        order = flow_order(ENERGIES, GROUPS, YEARS, keys, 5, spacing=2)
        self.assertEqual(order, [0, 1, 2, 3, 4])


class PrepareFlowAlbumTest(unittest.TestCase):
    def test_prepare_flow_separates_same_album(self):
        tracks = [
            Track(persistent_id="S1", name="Score 1", artist="Composer A",
                  album="Film Score", genre="Soundtrack", bpm=120),
            Track(persistent_id="S2", name="Score 2", artist="Singer B",
                  album="Film Score", genre="Soundtrack", bpm=120),
            Track(persistent_id="F1", name="Filler 1", artist="Artist C",
                  album="Album C", genre="Pop", bpm=120),
            Track(persistent_id="F2", name="Filler 2", artist="Artist D",
                  album="Album D", genre="Pop", bpm=120),
            Track(persistent_id="F3", name="Filler 3", artist="Artist E",
                  album="Album E", genre="Pop", bpm=120),
        ]
        ordered, energies, eligible = prepare_flow(
            tracks, Settings(flow_size=5, artist_spacing=2)
        )
        self.assertEqual(eligible, 5)
        self.assertEqual(len(ordered), 5)
        # BPM 120 scores 75; Pop adds the legacy +8, Soundtrack (group
        # 11) adds nothing on the BPM path.
        self.assertEqual(energies, [75, 83, 83, 75, 83])
        ids = [t.persistent_id for t in ordered]
        self.assertEqual(ids, ["S1", "F1", "F2", "S2", "F3"])
        self.assertGreaterEqual(abs(ids.index("S1") - ids.index("S2")), 3)


if __name__ == "__main__":
    unittest.main()
