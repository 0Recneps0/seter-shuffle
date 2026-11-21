"""Audit counts genre strings case-insensitively (2026-11-09 experimental).

The audit's top-genres list exists so the next genre-map edit is
driven by real data, but it counted raw genre strings, so "Rock",
"rock", and "ROCK" were three genres: genre_distinct was inflated
and the top-genres list split one genre across three lines. Flow
itself matches genres case-insensitively (a lowered substring
check), so the audit's counting contradicted how genres are actually
used. audit_library now groups by the lowercased string and keeps
the first-seen casing as the displayed label, so the counts match
the grouping Flow applies and the list still reads as the library
wrote it.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from seter_shuffle.audit import audit_library, format_audit
from seter_shuffle.tracks import Track

ROOT = Path(__file__).resolve().parents[1]


def _track(pid: str, genre: str) -> Track:
    return Track(persistent_id=pid, name=pid, artist="X", genre=genre)


class AuditGenreCaseTests(unittest.TestCase):
    def test_case_variants_are_one_genre(self):
        tracks = [_track("A", "Rock"), _track("B", "rock"), _track("C", "ROCK")]
        report = audit_library(tracks)
        self.assertEqual(report["genre_distinct"], 1)
        self.assertEqual(report["genre_counts"], [("Rock", 3)])

    def test_mixed_case_counts_stay_separate_genres(self):
        tracks = [
            _track("A", "Pop"), _track("B", "pop"), _track("C", "Jazz"),
        ]
        report = audit_library(tracks)
        self.assertEqual(report["genre_distinct"], 2)
        self.assertEqual(report["genre_counts"], [("Pop", 2), ("Jazz", 1)])

    def test_whitespace_and_case_merge(self):
        tracks = [_track("A", "  Hip-Hop "), _track("B", "hip-hop")]
        report = audit_library(tracks)
        self.assertEqual(report["genre_distinct"], 1)
        self.assertEqual(report["genre_counts"], [("Hip-Hop", 2)])

    def test_genre_present_unchanged_by_case(self):
        tracks = [
            _track("A", "Rock"), _track("B", "rock"), _track("C", ""),
            _track("D", "   "),
        ]
        report = audit_library(tracks)
        self.assertEqual(report["genre_present"], 2)
        self.assertEqual(report["genre_missing"], 2)
        self.assertEqual(report["genre_distinct"], 1)
        self.assertEqual(report["genre_counts"], [("Rock", 2)])

    def test_format_audit_lists_merged_genre_once(self):
        tracks = [_track("A", "Rock"), _track("B", "rock"), _track("C", "ROCK")]
        lines = format_audit(audit_library(tracks))
        self.assertIn("Genre: present 3 (100.0%), missing 0 (0.0%), 1 distinct.", lines)
        self.assertIn("      3  Rock", lines)
        self.assertEqual(sum(1 for line in lines if "ock" in line), 1)

    def test_cli_audit_lists_merged_genre_once(self):
        records = [
            {"persistent_id": "A", "name": "a", "artist": "X", "genre": "Rock"},
            {"persistent_id": "B", "name": "b", "artist": "Y", "genre": "rock"},
            {"persistent_id": "C", "name": "c", "artist": "Z", "genre": "ROCK"},
        ]
        with tempfile.TemporaryDirectory() as tmp:
            lib = Path(tmp) / "lib.json"
            lib.write_text(json.dumps(records), encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, "-m", "seter_shuffle.cli", "audit",
                 "--library", str(lib)],
                cwd=ROOT, capture_output=True, text=True,
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(
            "Genre: present 3 (100.0%), missing 0 (0.0%), 1 distinct.",
            proc.stdout,
        )
        self.assertIn("      3  Rock", proc.stdout)
        self.assertNotIn("rock", proc.stdout.replace("      3  Rock", ""))


if __name__ == "__main__":
    unittest.main()
