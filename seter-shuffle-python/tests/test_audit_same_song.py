"""Audit same-song counts (2026-11-01 experimental): the audit reports
how many library tracks are same-song copies of another track, using
the same conservative rule dedupe uses, so a dedupe total below the
library size has an explanation instead of looking like lost songs."""

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


def t(pid, artist="Noor", name="Quiet Room", dur=None):
    return Track(persistent_id=pid, artist=artist, name=name, duration_seconds=dur)


class AuditSameSongTests(unittest.TestCase):
    def test_no_duplicates_reports_zero(self):
        report = audit_library([t("1"), t("2", "Vector", "Drive")])
        self.assertEqual(report["same_song_groups"], 0)
        self.assertEqual(report["same_song_extra"], 0)
        lines = format_audit(report)
        self.assertIn(
            "Same-song duplicates: 0 extra copies across 0 songs "
            "(same artist + title stored as different library tracks).",
            lines,
        )

    def test_three_copies_are_one_group_with_two_extra(self):
        tracks = [
            t("a", dur=200.0),
            t("b", "Vector", "Drive"),
            t("c", dur=201.0),
            t("d", dur=199.0),
        ]
        report = audit_library(tracks)
        self.assertEqual(report["same_song_groups"], 1)
        self.assertEqual(report["same_song_extra"], 2)

    def test_two_groups_sum(self):
        tracks = [
            t("a"),
            t("b", "Vector", "Drive"),
            t("c"),
            t("d", "Vector", "Drive"),
            t("e", "Luna", "Tide"),
        ]
        report = audit_library(tracks)
        self.assertEqual(report["same_song_groups"], 2)
        self.assertEqual(report["same_song_extra"], 2)

    def test_same_title_different_artist_not_counted(self):
        tracks = [t("a"), t("b", "Vector", "Quiet Room")]
        report = audit_library(tracks)
        self.assertEqual(report["same_song_groups"], 0)
        self.assertEqual(report["same_song_extra"], 0)

    def test_different_lengths_not_counted(self):
        # Same artist + title but 10s apart: a live version or radio
        # edit, not a copy, per the dedupe rule.
        tracks = [t("a", dur=200.0), t("b", dur=210.0)]
        report = audit_library(tracks)
        self.assertEqual(report["same_song_groups"], 0)
        self.assertEqual(report["same_song_extra"], 0)

    def test_live_suffix_not_counted(self):
        tracks = [t("a"), t("b", name="Quiet Room (Live)")]
        report = audit_library(tracks)
        self.assertEqual(report["same_song_groups"], 0)
        self.assertEqual(report["same_song_extra"], 0)

    def test_case_and_whitespace_normalised(self):
        tracks = [t("a"), t("b", name="  quiet   ROOM ")]
        report = audit_library(tracks)
        self.assertEqual(report["same_song_groups"], 1)
        self.assertEqual(report["same_song_extra"], 1)

    def test_missing_artist_not_counted(self):
        tracks = [t("a"), t("b", artist="")]
        report = audit_library(tracks)
        self.assertEqual(report["same_song_groups"], 0)
        self.assertEqual(report["same_song_extra"], 0)

    def test_same_id_repeat_not_counted_as_same_song(self):
        # A repeated persistent ID is a dump error, not a same-song
        # library copy; the audit must not report it here.
        tracks = [t("a"), t("a")]
        report = audit_library(tracks)
        self.assertEqual(report["same_song_groups"], 0)
        self.assertEqual(report["same_song_extra"], 0)

    def test_cli_audit_prints_same_song_line(self):
        records = [
            {"persistent_id": "a", "name": "Quiet Room", "artist": "Noor"},
            {"persistent_id": "b", "name": "Quiet Room", "artist": "Noor"},
            {"persistent_id": "c", "name": "Drive", "artist": "Vector"},
        ]
        with tempfile.TemporaryDirectory() as tmp:
            lib = Path(tmp) / "lib.json"
            lib.write_text(json.dumps(records), encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, "-m", "seter_shuffle.cli", "audit", "--library", str(lib)],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(
            "Same-song duplicates: 1 extra copies across 1 songs",
            proc.stdout,
        )


if __name__ == "__main__":
    unittest.main()
