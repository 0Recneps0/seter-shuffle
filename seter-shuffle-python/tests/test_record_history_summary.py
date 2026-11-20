"""record-history prints a confirmation (2026-11-15 experimental).

Every other step of the daily run leaves a trace in the run log:
shuffle, flow, and rediscover print a header plus a full-list
summary, dedupe prints each removed duplicate, validate-order and
validate-backup print their verdict, library-manifest prints its
count. record-history was the exception: it appended the picked IDs
to the cooldown history file and printed nothing, so the daily log
had no visible proof the cooldown was actually recorded after a
successful Rediscover apply, and an empty IDs file would have
passed through just as silently. The command now prints one
confirmation line (count, history file, cooldown days), and the
honest variants when nothing was written. Print-only: it changes
no history rule, no file content, and no playlist. run.sh calls
this step through `step`, which tees stdout into the run log.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from seter_shuffle.rediscover import record_rediscover_history

ROOT = Path(__file__).resolve().parents[1]
TODAY = datetime(2026, 11, 15).date()


class RecordHistoryReturnTests(unittest.TestCase):
    def test_returns_number_appended(self):
        with tempfile.TemporaryDirectory() as tmp:
            history = Path(tmp) / "history.tsv"
            self.assertEqual(
                record_rediscover_history(
                    history, ["AAA", "BBB"], 14, today=TODAY
                ),
                2,
            )
            self.assertEqual(
                history.read_text(encoding="utf-8"),
                "2026-11-15\tAAA\n2026-11-15\tBBB\n",
            )

    def test_empty_ids_returns_zero_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            history = Path(tmp) / "history.tsv"
            self.assertEqual(
                record_rediscover_history(history, [], 14, today=TODAY), 0
            )
            self.assertFalse(history.exists())

    def test_zero_cooldown_returns_zero_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            history = Path(tmp) / "history.tsv"
            history.write_text("2026-11-01\tOLD1\n", encoding="utf-8")
            self.assertEqual(
                record_rediscover_history(
                    history, ["AAA"], 0, today=TODAY
                ),
                0,
            )
            self.assertEqual(
                history.read_text(encoding="utf-8"), "2026-11-01\tOLD1\n"
            )


class RecordHistoryCliTests(unittest.TestCase):
    def run_cli(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, "-m", "seter_shuffle.cli", *args],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )

    def test_cli_prints_confirmation(self):
        with tempfile.TemporaryDirectory() as tmp:
            history = Path(tmp) / "history.tsv"
            ids = Path(tmp) / "ids.txt"
            ids.write_text("AAA\nBBB\n", encoding="utf-8")
            result = self.run_cli(
                "record-history", "--history", str(history),
                "--ids-file", str(ids), "--today", "2026-11-15",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(
                f"History recorded: 2 IDs appended to {history} "
                "(cooldown 14 days).",
                result.stdout,
            )
            self.assertIn("2026-11-15\tAAA", history.read_text(encoding="utf-8"))
            self.assertIn("2026-11-15\tBBB", history.read_text(encoding="utf-8"))

    def test_cli_singular_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            history = Path(tmp) / "history.tsv"
            ids = Path(tmp) / "ids.txt"
            ids.write_text("AAA\n", encoding="utf-8")
            result = self.run_cli(
                "record-history", "--history", str(history),
                "--ids-file", str(ids), "--today", "2026-11-15",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("History recorded: 1 ID appended to", result.stdout)
            self.assertNotIn("1 IDs", result.stdout)

    def test_cli_empty_ids_file_says_nothing_appended(self):
        with tempfile.TemporaryDirectory() as tmp:
            history = Path(tmp) / "history.tsv"
            ids = Path(tmp) / "ids.txt"
            ids.write_text("", encoding="utf-8")
            result = self.run_cli(
                "record-history", "--history", str(history),
                "--ids-file", str(ids), "--today", "2026-11-15",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(
                "History recorded: 0 IDs; nothing appended (empty IDs file).",
                result.stdout,
            )
            self.assertFalse(history.exists())

    def test_cli_zero_cooldown_says_nothing_written(self):
        with tempfile.TemporaryDirectory() as tmp:
            history = Path(tmp) / "history.tsv"
            history.write_text("2026-11-01\tOLD1\n", encoding="utf-8")
            ids = Path(tmp) / "ids.txt"
            ids.write_text("AAA\n", encoding="utf-8")
            result = self.run_cli(
                "record-history", "--history", str(history),
                "--ids-file", str(ids), "--today", "2026-11-15",
                "--cooldown-days", "0",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(
                "History not recorded: cooldown is 0 days, nothing was written.",
                result.stdout,
            )
            self.assertEqual(
                history.read_text(encoding="utf-8"), "2026-11-01\tOLD1\n"
            )


if __name__ == "__main__":
    unittest.main()
