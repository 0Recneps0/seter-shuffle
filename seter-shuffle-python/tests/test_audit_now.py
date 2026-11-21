"""Audit Flow energies use the real clock (2026-11-08 experimental).

The audit's "Flow energies (eligible)" line used to score every track
clock-free, while Flow itself scores with the real clock (played-date
recency and date-added newness). For a library with recently played
or recently added songs the audit's range was wrong by up to 5 points
against what flowPreview actually builds: a song played 5 days ago
scores 56 in Flow but 53 in a clock-free audit. audit_library now
takes an optional `now`, and the CLI passes the real clock, so the
audit's range is the range Flow builds. Without `now` the old
deterministic behaviour is unchanged, and the BPM path never uses
`now` either way.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from seter_shuffle.audit import audit_library, format_audit
from seter_shuffle.flow import prepare_flow
from seter_shuffle.settings import Settings
from seter_shuffle.tracks import Track

ROOT = Path(__file__).resolve().parents[1]

NOW = datetime(2026, 11, 8, 12, 0, tzinfo=timezone.utc)


def _fixture() -> list[Track]:
    # Hand-computed fallback energies (no BPM, no genre, unrated,
    # not favorited, no skips, no year):
    #   A: 5 plays -> tier 3; played 5 days ago -> +3 with now.
    #      clock-free 53, with now 56.
    #   B: 5 plays -> tier 3; played 2024-01-01 -> over 730 days
    #      ago -> -2 with now. Clock-free 53, with now 51.
    #   C: 0 plays -> tier 0; added 7 days ago -> +2 with now.
    #      clock-free 50, with now 52.
    return [
        Track(
            persistent_id="A", name="Recent", artist="X", played_count=5,
            played_date=datetime(2026, 11, 3, 12, 0, tzinfo=timezone.utc),
        ),
        Track(
            persistent_id="B", name="Old", artist="Y", played_count=5,
            played_date=datetime(2024, 1, 1, 12, 0, tzinfo=timezone.utc),
        ),
        Track(
            persistent_id="C", name="New", artist="Z", played_count=0,
            date_added=datetime(2026, 11, 1, 12, 0, tzinfo=timezone.utc),
        ),
    ]


class AuditNowTests(unittest.TestCase):
    def test_without_now_ignores_recency(self):
        report = audit_library(_fixture())
        self.assertEqual(report["energy_min"], 50)
        self.assertEqual(report["energy_max"], 53)
        self.assertEqual(report["energy_distinct"], 2)
        self.assertEqual(report["energy_distinct_missing_bpm"], 2)

    def test_with_now_matches_flow_energies(self):
        report = audit_library(_fixture(), now=NOW)
        self.assertEqual(report["energy_min"], 51)
        self.assertEqual(report["energy_max"], 56)
        self.assertEqual(report["energy_distinct"], 3)
        self.assertEqual(report["energy_distinct_missing_bpm"], 3)
        # The contract itself: the audit's energies are Flow's
        # energies on the same dump at the same reference time.
        _ordered, flow_energies, _eligible = prepare_flow(
            _fixture(), Settings(), now=NOW
        )
        self.assertEqual(sorted(flow_energies), [51, 52, 56])

    def test_with_now_bpm_path_unaffected(self):
        # BPM 120, Pop: band 75 + legacy genre nudge 8 = 83, and the
        # BPM path never applies the recency nudge, however recent
        # the play date is.
        bpm_track = Track(
            persistent_id="D", name="BPM", artist="W", genre="Pop",
            bpm=120, played_count=0,
            played_date=datetime(2026, 11, 7, 12, 0, tzinfo=timezone.utc),
        )
        tracks = _fixture() + [bpm_track]
        self.assertEqual(
            audit_library(tracks)["energy_max"],
            audit_library(tracks, now=NOW)["energy_max"],
        )
        self.assertEqual(audit_library(tracks, now=NOW)["energy_max"], 83)
        self.assertEqual(audit_library(tracks, now=NOW)["energy_distinct"], 4)

    def test_format_audit_prints_clock_based_range(self):
        lines = format_audit(audit_library(_fixture(), now=NOW))
        self.assertIn(
            "Flow energies (eligible): 51..56, 3 distinct values; "
            "3 distinct among missing-BPM songs.",
            lines,
        )

    def test_cli_audit_prints_clock_based_range(self):
        # Nudges that are stable whatever the clock says when the
        # test runs: played 2020-01-01 is always over 730 days ago
        # (-2), added 2020-01-01 is never new, so the CLI's real
        # clock gives exact numbers: E 51, F 50.
        records = [
            {"persistent_id": "E", "name": "Old", "artist": "X",
             "played_count": 5, "played_date": "2020-01-01T12:00:00Z"},
            {"persistent_id": "F", "name": "Plain", "artist": "Y",
             "played_count": 0},
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
            "Flow energies (eligible): 50..51, 2 distinct values; "
            "2 distinct among missing-BPM songs.",
            proc.stdout,
        )
        self.assertIn("Nothing was changed.", proc.stdout)


if __name__ == "__main__":
    unittest.main()
