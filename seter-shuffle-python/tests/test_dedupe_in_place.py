"""In-place dedupe (v3.0.9).

Spencer's cap, 2026-10-30: dedupe must rebuild his playlist
1-2 times max. The in-place answer is 0 rebuilds on success:
only the duplicate entries are deleted, every other song
stays exactly where it was, so no mapping, probe, or trial
is needed at all, and no mapping is recorded.

Tested here, without a Mac:
  * The bridge script exists and has the in-place handlers:
    snapshot before deleting, descending-index validation,
    presence verification, both-mappings restore on failure,
    and a delete loop that never rebuilds on the success path.
  * run.sh's dedupe case calls dedupe_in_place, never
    apply_order_mapped for dedupe, and dedupe_in_place calls
    the bridge with order, delete-indices, and run-backup files.
  * The Python delete-positions command returns exactly the
    duplicate positions, strictly descending, for both match
    modes, including same-song entries with different IDs.
  * The success path installs no mapping file (covered by the
    harness tests in test_trial_dedupe.py, which run the real
    run.sh dedupe case against a fake osascript).
"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class DedupeInPlaceStructuralTests(unittest.TestCase):
    def test_bridge_has_in_place_handlers(self) -> None:
        text = (ROOT / "bridge" / "dedupe-in-place.applescript").read_text(encoding="utf-8")
        self.assertIn("on run argv", text)
        self.assertIn("writeBackupAtomically", text)
        self.assertIn("delete item idxVal of songTracks", text)
        self.assertIn("strictly descending", text)
        self.assertIn("verifyPresence", text)
        self.assertIn("tryRestoreBothMappings", text)
        # Success returns without any rebuild call: the only
        # rebuildList use is inside the restore handler.
        self.assertEqual(text.count("my rebuildList"), 1)

    def test_run_sh_dedupe_case_is_in_place(self) -> None:
        text = (ROOT / "run.sh").read_text(encoding="utf-8")
        dedupe_block = text.split("  dedupe)\n", 1)[1].split("    ;;\n", 1)[0]
        self.assertIn('dedupe_in_place "$TARGET_PLAYLIST"', dedupe_block)
        self.assertNotIn('apply_order_mapped "$TARGET_PLAYLIST" "dedupe"', dedupe_block)
        self.assertIn("dedupe-in-place.applescript", text)
        self.assertIn("dedupe-positions", text)

    def test_dedupe_positions_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            dump = base / "library.json"
            dump.write_text(
                json.dumps(
                    {
                        "tracks": [
                            {
                                "persistent_id": "A",
                                "name": "Song",
                                "artist": "Artist",
                                "genre": "Pop",
                                "bpm": 120,
                                "year": 2020,
                                "played_count": 5,
                                "played_date": "2024-01-01T00:00:00Z",
                                "date_added": "2020-01-01T00:00:00Z",
                                "duration_ms": 180000,
                            },
                            {
                                "persistent_id": "B",
                                "name": "Other",
                                "artist": "Artist",
                                "genre": "Pop",
                                "bpm": 120,
                                "year": 2020,
                                "played_count": 5,
                                "played_date": "2024-01-01T00:00:00Z",
                                "date_added": "2020-01-01T00:00:00Z",
                                "duration_ms": 200000,
                            },
                            {
                                "persistent_id": "A",
                                "name": "Song",
                                "artist": "Artist",
                                "genre": "Pop",
                                "bpm": 120,
                                "year": 2020,
                                "played_count": 5,
                                "played_date": "2024-01-01T00:00:00Z",
                                "date_added": "2020-01-01T00:00:00Z",
                                "duration_ms": 180000,
                            },
                            {
                                # Same song as A, different library track.
                                "persistent_id": "C",
                                "name": "Song",
                                "artist": "Artist",
                                "genre": "Pop",
                                "bpm": 120,
                                "year": 2020,
                                "played_count": 5,
                                "played_date": "2024-01-01T00:00:00Z",
                                "date_added": "2020-01-01T00:00:00Z",
                                "duration_ms": 181000,
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )
            out = base / "positions.txt"
            result = subprocess.run(
                [
                    "python3",
                    "-m",
                    "seter_shuffle.cli",
                    "dedupe-positions",
                    "--library",
                    str(dump),
                    "--match",
                    "song",
                    "--out",
                    str(out),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=60,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            # Positions 4 (same song) and 3 (same ID), descending.
            self.assertEqual(out.read_text(encoding="utf-8").split(), ["4", "3"])
            out_id = base / "positions-id.txt"
            result = subprocess.run(
                [
                    "python3",
                    "-m",
                    "seter_shuffle.cli",
                    "dedupe-positions",
                    "--library",
                    str(dump),
                    "--match",
                    "id",
                    "--out",
                    str(out_id),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=60,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            # ID mode leaves the same-song entry alone.
            self.assertEqual(out_id.read_text(encoding="utf-8").split(), ["3"])


if __name__ == "__main__":
    unittest.main()
