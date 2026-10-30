"""Tests for the bridge safety gates (Python side).

These tests cover everything about bridge safety that CAN be proven
without a Mac: the order/backup validation rules that run.sh applies
before osascript ever runs. The AppleScript itself cannot run here
(no osascript, no Music), so its half of the contract (atomic backup,
exact-order verify, restore-on-failure, unambiguous playlist
resolution) is documented in BRIDGE-SAFETY.md with a Mac verification
procedure, and is NOT faked into passing here.

Run from the project root:
    python3 -m unittest discover -s tests -v
"""

from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.cli import main as cli_main
from seter_shuffle.validate import (
    validate_backup_file,
    validate_order_file,
    validate_order_text,
)


def _track(pid: str, **overrides: object) -> dict:
    base = {
        "persistent_id": pid,
        "name": pid,
        "artist": "Artist",
        "genre": "Pop",
        "bpm": 120,
        "year": 2020,
        "played_count": 5,
        "played_date": "2024-01-01T00:00:00Z",
        "date_added": "2020-01-01T00:00:00Z",
    }
    base.update(overrides)
    return base


class _TempFiles(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write_library(self, tracks: list[dict]) -> Path:
        path = self.dir / "library.json"
        path.write_text(json.dumps({"tracks": tracks}), encoding="utf-8")
        return path

    def write_txt(self, lines: list[str], trailing_newline: bool = True) -> Path:
        path = self.dir / "order.txt"
        text = "\n".join(lines) + ("\n" if trailing_newline else "")
        path.write_text(text, encoding="utf-8")
        return path

    def write_order_json(self, ids: list[str]) -> Path:
        path = self.dir / "order.json"
        path.write_text(
            json.dumps({"command": "flow", "ids": ids, "count": len(ids)}),
            encoding="utf-8",
        )
        return path


class OrderValidationTests(_TempFiles):
    def test_valid_shuffle_passes(self):
        lib = self.write_library([_track("A"), _track("B"), _track("C")])
        order = self.write_txt(["B", "A", "C"])
        self.assertEqual(
            validate_order_file(lib, order, mode="shuffle"), ["B", "A", "C"]
        )

    def test_empty_order_is_refused(self):
        lib = self.write_library([_track("A")])
        order = self.write_txt([])
        with self.assertRaisesRegex(ValueError, "empty"):
            validate_order_file(lib, order)

    def test_duplicate_ids_are_refused(self):
        lib = self.write_library([_track("A"), _track("B")])
        order = self.write_txt(["A", "B", "A"])
        with self.assertRaisesRegex(ValueError, "duplicate"):
            validate_order_file(lib, order)

    def test_missing_id_is_refused_and_listed(self):
        lib = self.write_library([_track("A"), _track("B")])
        order = self.write_txt(["A", "GONE"])
        with self.assertRaisesRegex(ValueError, "GONE"):
            validate_order_file(lib, order)

    def test_shuffle_missing_a_dump_song_is_refused(self):
        lib = self.write_library([_track("A"), _track("B"), _track("C")])
        order = self.write_txt(["A", "B"])
        with self.assertRaisesRegex(ValueError, "exactly"):
            validate_order_file(lib, order, mode="shuffle")

    def test_shuffle_with_an_extra_id_is_refused(self):
        lib = self.write_library([_track("A"), _track("B")])
        order = self.write_txt(["A", "B", "C"])
        with self.assertRaisesRegex(ValueError, "not in the library"):
            validate_order_file(lib, order, mode="shuffle")

    def test_blank_line_in_the_middle_is_refused(self):
        lib = self.write_library([_track("A"), _track("B")])
        path = self.dir / "order.txt"
        path.write_text("A\n\nB\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "blank"):
            validate_order_file(lib, path)

    def test_whitespace_padded_id_is_refused(self):
        lib = self.write_library([_track("A"), _track("B")])
        path = self.dir / "order.txt"
        path.write_text("A\n B\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "whitespace"):
            validate_order_file(lib, path)

    def test_order_json_mismatch_is_refused(self):
        lib = self.write_library([_track("A"), _track("B"), _track("C")])
        order = self.write_txt(["A", "B", "C"])
        order_json = self.write_order_json(["A", "C", "B"])
        with self.assertRaisesRegex(ValueError, "does not match order JSON"):
            validate_order_file(lib, order, order_json_path=order_json)

    def test_truncated_text_file_is_refused(self):
        # The classic case the bridge alone cannot see: a text file
        # cut short still "verifies" against itself, so the JSON
        # agreement check is what catches it.
        lib = self.write_library([_track("A"), _track("B"), _track("C")])
        order = self.write_txt(["A", "B"])
        order_json = self.write_order_json(["A", "B", "C"])
        with self.assertRaisesRegex(ValueError, "does not match order JSON"):
            validate_order_file(lib, order, order_json_path=order_json)

    def test_order_json_agreement_passes(self):
        lib = self.write_library([_track("A"), _track("B")])
        order = self.write_txt(["B", "A"])
        order_json = self.write_order_json(["B", "A"])
        self.assertEqual(
            validate_order_file(lib, order, order_json_path=order_json),
            ["B", "A"],
        )

    def test_expected_count_mismatch_is_refused(self):
        lib = self.write_library([_track("A"), _track("B")])
        order = self.write_txt(["A", "B"])
        with self.assertRaisesRegex(ValueError, "expected"):
            validate_order_file(lib, order, expected_count=3)

    def test_flow_rejects_disliked_and_unchecked(self):
        lib = self.write_library(
            [_track("A"), _track("B", disliked=True), _track("C", enabled=False)]
        )
        with self.assertRaisesRegex(ValueError, "ineligible"):
            validate_order_file(lib, self.write_txt(["A", "B"]), mode="flow")
        with self.assertRaisesRegex(ValueError, "ineligible"):
            validate_order_file(lib, self.write_txt(["A", "C"]), mode="flow")
        self.assertEqual(
            validate_order_file(lib, self.write_txt(["A"]), mode="flow"), ["A"]
        )

    def test_rediscover_rejects_ineligible(self):
        lib = self.write_library([_track("A"), _track("B", disliked=True)])
        with self.assertRaisesRegex(ValueError, "ineligible"):
            validate_order_file(lib, self.write_txt(["B"]), mode="rediscover")

    def test_missing_order_file_is_refused(self):
        lib = self.write_library([_track("A")])
        with self.assertRaisesRegex(ValueError, "cannot read"):
            validate_order_file(lib, self.dir / "nope.txt")

    def test_non_utf8_order_file_is_refused(self):
        lib = self.write_library([_track("A")])
        path = self.dir / "order.txt"
        path.write_bytes(b"A\n\xff\n")
        with self.assertRaisesRegex(ValueError, "UTF-8"):
            validate_order_file(lib, path)

    def test_malformed_dump_is_refused(self):
        path = self.dir / "library.json"
        path.write_text("{not json", encoding="utf-8")
        order = self.write_txt(["A"])
        with self.assertRaises(ValueError):
            validate_order_file(path, order)


class BackupValidationTests(_TempFiles):
    def test_valid_backup_passes(self):
        path = self.dir / "backup.txt"
        path.write_text("A\nB\nC", encoding="utf-8")
        self.assertEqual(validate_backup_file(path), ["A", "B", "C"])

    def test_empty_backup_is_valid(self):
        # An empty backup snapshots an empty playlist (first-run
        # playlist). Undo of it restores an empty playlist.
        path = self.dir / "backup.txt"
        path.write_text("", encoding="utf-8")
        self.assertEqual(validate_backup_file(path), [])

    def test_backup_duplicates_are_allowed(self):
        # A real playlist can hold the same song twice, so a backup
        # may legitimately repeat an ID. Orders may not; backups may.
        path = self.dir / "backup.txt"
        path.write_text("A\nB\nA\n", encoding="utf-8")
        self.assertEqual(validate_backup_file(path), ["A", "B", "A"])

    def test_missing_backup_is_refused(self):
        with self.assertRaisesRegex(ValueError, "cannot read"):
            validate_backup_file(self.dir / "nope.txt")

    def test_backup_blank_middle_line_is_refused(self):
        path = self.dir / "backup.txt"
        path.write_text("A\n\nB\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "blank"):
            validate_backup_file(path)

    def test_backup_whitespace_id_is_refused(self):
        path = self.dir / "backup.txt"
        path.write_text("A\nB \n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "whitespace"):
            validate_backup_file(path)


class InMemoryValidationTests(unittest.TestCase):
    def test_in_memory_rules(self):
        lib_ids = {"A", "B"}
        with self.assertRaisesRegex(ValueError, "empty"):
            validate_order_text([], lib_ids)
        with self.assertRaisesRegex(ValueError, "duplicate"):
            validate_order_text(["A", "A"], lib_ids)
        with self.assertRaisesRegex(ValueError, "not in library"):
            validate_order_text(["A", "X"], lib_ids)
        with self.assertRaisesRegex(ValueError, "exactly"):
            validate_order_text(["A"], lib_ids, mode="shuffle")
        validate_order_text(["B", "A"], lib_ids, mode="shuffle")


class CliValidationTests(_TempFiles):
    def _run_cli(self, argv: list[str]) -> int:
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            return cli_main(argv)

    def test_cli_validate_order_success_and_failure(self):
        lib = self.write_library([_track("A"), _track("B")])
        good = self.write_txt(["B", "A"])
        self.assertEqual(
            self._run_cli(
                ["validate-order", "--library", str(lib), "--order-txt", str(good),
                 "--mode", "shuffle"]
            ),
            0,
        )
        bad = self.dir / "bad.txt"
        bad.write_text("A\nA\n", encoding="utf-8")
        self.assertEqual(
            self._run_cli(
                ["validate-order", "--library", str(lib), "--order-txt", str(bad)]
            ),
            2,
        )

    def test_cli_validate_backup_success_and_failure(self):
        good = self.dir / "good.txt"
        good.write_text("A\nB\n", encoding="utf-8")
        self.assertEqual(
            self._run_cli(["validate-backup", "--backup", str(good)]), 0
        )
        self.assertEqual(
            self._run_cli(
                ["validate-backup", "--backup", str(self.dir / "missing.txt")]
            ),
            2,
        )


if __name__ == "__main__":
    unittest.main()
