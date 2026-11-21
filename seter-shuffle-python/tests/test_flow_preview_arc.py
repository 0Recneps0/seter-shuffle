"""Flow preview arc summary (2026-11-02 experimental).

flowPreview prints only the first preview_show songs, so a flat first
page used to hide whether the full Flow order actually rises and
falls. The new summary line covers the whole ordered list: size,
energy range, first and last energies, and the peak position.
Preview only: it changes no order, no file, and no playlist.

2026-11-13 experimental: the real `flow` command prints the same
line. A real Flow run used to log only the first 25 songs too, so
the daily run log hid whether the applied order actually rose and
fell; the line now lands in that log as well. Still print-only: it
describes an order already computed.
"""

from __future__ import annotations

import json
import random
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from seter_shuffle.flow import flow_arc_summary, prepare_flow
from seter_shuffle.settings import Settings

ROOT = Path(__file__).resolve().parents[1]


class FlowArcSummaryTests(unittest.TestCase):
    def test_empty_returns_none(self):
        self.assertIsNone(flow_arc_summary([]))

    def test_single_song(self):
        self.assertEqual(
            flow_arc_summary([50]),
            "Flow arc: 1 song, energies 50..50, starts 50, peaks 50 at #1, ends 50.",
        )

    def test_rise_and_fall(self):
        self.assertEqual(
            flow_arc_summary([45, 60, 90, 70, 40]),
            "Flow arc: 5 songs, energies 40..90, starts 45, peaks 90 at #3, ends 40.",
        )

    def test_flat_list_peaks_at_first_position(self):
        self.assertEqual(
            flow_arc_summary([50, 50, 50]),
            "Flow arc: 3 songs, energies 50..50, starts 50, peaks 50 at #1, ends 50.",
        )

    def test_tied_peak_uses_first_peak(self):
        self.assertEqual(
            flow_arc_summary([40, 90, 90, 50]),
            "Flow arc: 4 songs, energies 40..90, starts 40, peaks 90 at #2, ends 50.",
        )

    def test_cli_flow_preview_prints_summary_for_full_list(self):
        # BPM tracks only, so energies do not depend on the CLI's
        # real-clock recency nudge and the expected order can be
        # recomputed exactly here.
        records = []
        bpms = [70, 90, 110, 130, 150, 170]
        for i in range(30):
            records.append({
                "persistent_id": f"T{i:02d}",
                "name": f"Song {i}",
                "artist": f"Artist {i}",
                "genre": "Pop",
                "bpm": bpms[i % len(bpms)],
                "played_count": 0,
                "rating": 0,
            })
        with tempfile.TemporaryDirectory() as tmp:
            lib = Path(tmp) / "lib.json"
            lib.write_text(json.dumps(records), encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, "-m", "seter_shuffle.cli", "flowPreview",
                 "--library", str(lib), "--seed", "7"],
                cwd=ROOT, capture_output=True, text=True,
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Nothing was changed.", proc.stdout)
        # Recompute the expected order the same way the CLI does:
        # BPM path, so `now` does not affect energies.
        from seter_shuffle.tracks import track_from_dict

        lib_tracks = [track_from_dict(r) for r in records]
        _ordered, energies, _eligible = prepare_flow(
            lib_tracks, Settings(), random.Random(7))
        expected = flow_arc_summary(energies)
        self.assertIsNotNone(expected)
        self.assertEqual(len(energies), 30)
        self.assertIn(expected, proc.stdout)
        # The summary is the last line: it comes after the capped
        # preview list, not buried in it.
        self.assertEqual(proc.stdout.rstrip().splitlines()[-1], expected)

    def test_cli_plain_flow_prints_summary(self):
        # 2026-11-13: the real `flow` command prints the same arc
        # line as flowPreview, so the daily run log shows whether
        # the applied order actually rises and falls. 30 songs so
        # the preview list is capped at 25 and only the summary
        # covers the full order.
        records = []
        bpms = [70, 90, 110, 130, 150, 170]
        for i in range(30):
            records.append({
                "persistent_id": f"T{i:02d}",
                "name": f"Song {i}",
                "artist": f"Artist {i}",
                "genre": "Pop",
                "bpm": bpms[i % len(bpms)],
                "played_count": 0,
                "rating": 0,
            })
        with tempfile.TemporaryDirectory() as tmp:
            lib = Path(tmp) / "lib.json"
            lib.write_text(json.dumps(records), encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, "-m", "seter_shuffle.cli", "flow",
                 "--library", str(lib), "--seed", "7"],
                cwd=ROOT, capture_output=True, text=True,
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn("Nothing was changed.", proc.stdout)
        from seter_shuffle.tracks import track_from_dict

        lib_tracks = [track_from_dict(r) for r in records]
        _ordered, energies, _eligible = prepare_flow(
            lib_tracks, Settings(), random.Random(7))
        expected = flow_arc_summary(energies)
        self.assertIsNotNone(expected)
        self.assertEqual(len(energies), 30)
        self.assertIn(expected, proc.stdout)
        self.assertEqual(proc.stdout.rstrip().splitlines()[-1], expected)

    def test_cli_plain_flow_quiet_suppresses_summary(self):
        records = [
            {"persistent_id": f"T{i:02d}", "name": f"Song {i}",
             "artist": f"Artist {i}", "genre": "Pop", "bpm": 120}
            for i in range(5)
        ]
        with tempfile.TemporaryDirectory() as tmp:
            lib = Path(tmp) / "lib.json"
            lib.write_text(json.dumps(records), encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, "-m", "seter_shuffle.cli", "flow",
                 "--library", str(lib), "--seed", "7", "--quiet"],
                cwd=ROOT, capture_output=True, text=True,
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn("Flow arc:", proc.stdout)
        self.assertEqual(proc.stdout, "")


if __name__ == "__main__":
    unittest.main()
