"""Rediscover pick summary (2026-11-07 experimental, extended 2026-11-14).

rediscover-preview prints only the first preview_show songs, so the
first page hid what the full pick list is actually made of: how much
of it was never played at all, how much is favorited or highly
rated, how long the picks were forgotten, and whether one artist
dominates the list. The new summary line covers the whole ordered
list. Since 2026-11-14 the plain `rediscover` command prints the
same line: its stdout is only logged by run.sh, so the daily run
log hid the same thing. Print-only: it changes no picks, no file,
and no playlist.
"""

from __future__ import annotations

import json
import random
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from seter_shuffle.rediscover import pick_rediscover, rediscover_summary
from seter_shuffle.settings import Settings
from seter_shuffle.tracks import Track, track_from_dict

ROOT = Path(__file__).resolve().parents[1]
NOW = datetime(2026, 1, 1, tzinfo=timezone.utc)


def _track(pid: str, **fields: object) -> Track:
    record = {
        "persistent_id": pid,
        "name": f"Song {pid}",
        "artist": "Artist",
        "played_count": 0,
    }
    record.update(fields)
    return track_from_dict(record)


class RediscoverSummaryTests(unittest.TestCase):
    def test_empty_returns_none(self):
        self.assertIsNone(rediscover_summary([], NOW))

    def test_single_song(self):
        picks = [_track("T1", artist="Solo")]
        self.assertEqual(
            rediscover_summary(picks, None),
            "Rediscover picks: 1 song, 1 never played, 0 favorited, "
            "0 rated 4-5 stars, max 1 per artist.",
        )

    def test_mixed_counts_and_forgotten_range(self):
        picks = [
            _track("T1", artist="A", played_count=0, favorited=True,
                   rating=100, date_added="2025-01-01T00:00:00Z"),
            _track("T2", artist="A", played_count=5, rating=80,
                   played_date="2025-07-01T00:00:00Z"),
            _track("T3", artist="B", played_count=10,
                   played_date="2024-01-01T00:00:00Z"),
            _track("T4", artist="B", played_count=0),
        ]
        self.assertEqual(
            rediscover_summary(picks, NOW),
            "Rediscover picks: 4 songs, 2 never played, 1 favorited, "
            "2 rated 4-5 stars, forgotten 184..731 days, max 2 per artist.",
        )

    def test_no_dates_omits_forgotten_clause(self):
        picks = [_track("T1", artist="A", played_count=3)]
        self.assertEqual(
            rediscover_summary(picks, NOW),
            "Rediscover picks: 1 song, 0 never played, 0 favorited, "
            "0 rated 4-5 stars, max 1 per artist.",
        )

    def test_no_now_omits_forgotten_clause(self):
        picks = [
            _track("T1", artist="A", played_count=5,
                   played_date="2025-01-01T00:00:00Z"),
        ]
        self.assertNotIn("forgotten", rediscover_summary(picks, None))

    def test_future_date_clamps_to_zero_days(self):
        picks = [
            _track("T1", artist="A", played_count=5,
                   played_date="2026-06-01T00:00:00Z"),
        ]
        self.assertIn("forgotten 0..0 days", rediscover_summary(picks, NOW))

    def test_empty_artist_does_not_inflate_max(self):
        picks = [
            _track("T1", artist="", played_count=3),
            _track("T2", artist="", played_count=3),
            _track("T3", artist="A", played_count=3),
            _track("T4", artist="A", played_count=3),
        ]
        self.assertEqual(
            rediscover_summary(picks, None),
            "Rediscover picks: 4 songs, 0 never played, 0 favorited, "
            "0 rated 4-5 stars, max 2 per artist.",
        )

    def test_no_named_artist_omits_max_clause(self):
        picks = [_track("T1", artist="", played_count=3)]
        self.assertEqual(
            rediscover_summary(picks, None),
            "Rediscover picks: 1 song, 0 never played, 0 favorited, "
            "0 rated 4-5 stars.",
        )

    def test_featuring_counts_as_main_artist(self):
        picks = [
            _track("T1", artist="Vector", played_count=3),
            _track("T2", artist="Vector feat. Luna", played_count=3),
        ]
        self.assertIn("max 2 per artist", rediscover_summary(picks, None))

    def test_cli_rediscover_preview_prints_summary_for_full_list(self):
        # No dates anywhere, so eligibility and weights do not depend
        # on the CLI's real clock and the expected picks can be
        # recomputed exactly here.
        records = []
        for i in range(30):
            records.append({
                "persistent_id": f"T{i:02d}",
                "name": f"Song {i}",
                "artist": f"Artist {i % 10}",
                "played_count": 0,
                "rating": 100 if i % 6 == 0 else 0,
                "favorited": i % 5 == 0,
            })
        with tempfile.TemporaryDirectory() as tmp:
            lib = Path(tmp) / "lib.json"
            lib.write_text(json.dumps(records), encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, "-m", "seter_shuffle.cli", "rediscover-preview",
                 "--library", str(lib), "--seed", "7"],
                cwd=ROOT, capture_output=True, text=True,
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Nothing was changed.", proc.stdout)
        # Recompute the expected picks the same way the CLI does:
        # no dates, so `now` does not affect them.
        lib_tracks = [track_from_dict(r) for r in records]
        picks, _candidates, _target = pick_rediscover(
            lib_tracks, NOW, Settings(), set(), random.Random(7)
        )
        expected = rediscover_summary(picks, None)
        self.assertIsNotNone(expected)
        self.assertEqual(len(picks), 30)
        self.assertIn(expected, proc.stdout)
        # The summary is the last line, after the capped preview list.
        self.assertEqual(proc.stdout.rstrip().splitlines()[-1], expected)
        # And it covers the whole list, not just the 25 shown.
        self.assertIn("30 songs", expected)
        self.assertIn("... and 5 more", proc.stdout)

    def test_cli_plain_rediscover_prints_summary_for_full_list(self):
        # The plain rediscover command prints the same summary line
        # as rediscover-preview, over the same full pick list.
        records = []
        for i in range(30):
            records.append({
                "persistent_id": f"T{i:02d}",
                "name": f"Song {i}",
                "artist": f"Artist {i % 10}",
                "played_count": 0,
                "rating": 100 if i % 6 == 0 else 0,
                "favorited": i % 5 == 0,
            })
        with tempfile.TemporaryDirectory() as tmp:
            lib = Path(tmp) / "lib.json"
            lib.write_text(json.dumps(records), encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, "-m", "seter_shuffle.cli", "rediscover",
                 "--library", str(lib), "--seed", "7"],
                cwd=ROOT, capture_output=True, text=True,
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn("Nothing was changed.", proc.stdout)
        # Recompute the expected picks the same way the CLI does:
        # no dates, so `now` does not affect them.
        lib_tracks = [track_from_dict(r) for r in records]
        picks, _candidates, _target = pick_rediscover(
            lib_tracks, NOW, Settings(), set(), random.Random(7)
        )
        expected = rediscover_summary(picks, None)
        self.assertIsNotNone(expected)
        self.assertEqual(len(picks), 30)
        self.assertIn(expected, proc.stdout)
        # The summary is the last line, after the capped preview list.
        self.assertEqual(proc.stdout.rstrip().splitlines()[-1], expected)
        # And it covers the whole list, not just the 25 shown.
        self.assertIn("30 songs", expected)
        self.assertIn("... and 5 more", proc.stdout)

    def test_cli_rediscover_quiet_prints_nothing(self):
        records = [
            {"persistent_id": f"T{i:02d}", "name": f"Song {i}",
             "artist": f"Artist {i}", "played_count": 0}
            for i in range(5)
        ]
        with tempfile.TemporaryDirectory() as tmp:
            lib = Path(tmp) / "lib.json"
            lib.write_text(json.dumps(records), encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, "-m", "seter_shuffle.cli", "rediscover",
                 "--library", str(lib), "--seed", "7", "--quiet"],
                cwd=ROOT, capture_output=True, text=True,
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "")


if __name__ == "__main__":
    unittest.main()
