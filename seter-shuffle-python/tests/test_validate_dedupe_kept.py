"""Tests for the 2026-11-10 fix: validate_order_text dedupe mode
accepts a same-song dedupe order when the caller supplies the kept set.

The bug, verified live before the fix: two different library IDs can
be the same song (a single plus the album version), and dedupe keeps
only one of them. The file form (validate_order_file) recomputes the
kept set from the dump and accepted the order ["A", "C"] for a
library of A + B (same song as A) + C. The in-memory form only saw
IDs, so it demanded every unique ID exactly once and refused that
same correct order. The fix is an optional dedupe_kept_ids
parameter: pass the kept set split_duplicates computes and the
in-memory check applies the same set rule as the file form. Without
it the old ID-level behaviour is preserved, and it is documented
rather than silently changed.
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.tracks import Track, split_duplicates
from seter_shuffle.validate import validate_order_file, validate_order_text


def _tracks() -> list[Track]:
    # A and B are the same song (same artist + title, lengths within
    # tolerance) stored as two library tracks; C is a distinct song.
    return [
        Track(persistent_id="A", name="Song X", artist="Drake",
              duration_seconds=200.0),
        Track(persistent_id="B", name="Song X", artist="Drake",
              duration_seconds=201.0),
        Track(persistent_id="C", name="Song Y", artist="Adele",
              duration_seconds=180.0),
    ]


def _kept_ids() -> set[str]:
    kept, _removed = split_duplicates(_tracks(), "song")
    return {t.persistent_id for t in kept}


class DedupeKeptIdsTests(unittest.TestCase):
    def test_same_song_order_passes_with_kept_set(self):
        # The fixed case: B is the same song as A, so the correct
        # dedupe order keeps A and C only.
        self.assertEqual(_kept_ids(), {"A", "C"})
        validate_order_text(
            ["A", "C"], {"A", "B", "C"}, mode="dedupe",
            dedupe_kept_ids={"A", "C"},
        )

    def test_same_song_order_refused_without_kept_set(self):
        # ID-only callers cannot know B is the same song as A, so
        # without the kept set the old rule still applies: every
        # unique ID exactly once. Documented, not silently changed.
        with self.assertRaises(ValueError):
            validate_order_text(["A", "C"], {"A", "B", "C"}, mode="dedupe")

    def test_dropping_a_kept_song_still_refused(self):
        with self.assertRaises(ValueError):
            validate_order_text(
                ["A"], {"A", "B", "C"}, mode="dedupe",
                dedupe_kept_ids={"A", "C"},
            )

    def test_repeat_still_refused_with_kept_set(self):
        with self.assertRaises(ValueError):
            validate_order_text(
                ["A", "C", "A"], {"A", "B", "C"}, mode="dedupe",
                dedupe_kept_ids={"A", "C"},
            )

    def test_invented_id_still_refused_with_kept_set(self):
        with self.assertRaises(ValueError):
            validate_order_text(
                ["A", "C", "ZZZ"], {"A", "B", "C"}, mode="dedupe",
                dedupe_kept_ids={"A", "C"},
            )

    def test_kept_set_may_reorder(self):
        validate_order_text(
            ["C", "A"], {"A", "B", "C"}, mode="dedupe",
            dedupe_kept_ids={"A", "C"},
        )

    def test_kept_set_ignored_outside_dedupe_mode(self):
        # The parameter only changes the dedupe check: a shuffle
        # order must still be exactly the library set.
        with self.assertRaises(ValueError):
            validate_order_text(
                ["A", "C"], {"A", "B", "C"}, mode="shuffle",
                dedupe_kept_ids={"A", "C"},
            )
        validate_order_text(
            ["C", "B", "A"], {"A", "B", "C"}, mode="shuffle",
            dedupe_kept_ids={"A", "C"},
        )

    def test_agrees_with_file_form(self):
        # The two forms must give the same answer on the same
        # library: the file form recomputes the kept set itself.
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            dump = directory / "library.json"
            dump.write_text(json.dumps({"tracks": [
                {"persistent_id": "A", "name": "Song X", "artist": "Drake",
                 "duration_ms": 200000},
                {"persistent_id": "B", "name": "Song X", "artist": "Drake",
                 "duration_ms": 201000},
                {"persistent_id": "C", "name": "Song Y", "artist": "Adele",
                 "duration_ms": 180000},
            ]}), encoding="utf-8")
            order_txt = directory / "order.txt"
            order_txt.write_text("A\nC\n", encoding="utf-8")
            self.assertEqual(
                validate_order_file(dump, order_txt, mode="dedupe"),
                ["A", "C"],
            )
            # And the in-memory form with the kept set agrees.
            validate_order_text(
                ["A", "C"], {"A", "B", "C"}, mode="dedupe",
                dedupe_kept_ids=_kept_ids(),
            )


if __name__ == "__main__":
    unittest.main()
