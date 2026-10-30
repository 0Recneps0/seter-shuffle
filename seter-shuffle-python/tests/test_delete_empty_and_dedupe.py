"""Tests for the 2026-10-29.2 fixes: delete-empty verification, the
mapping-capture bug, per-run backups, and the dedupe command.

What these tests CAN prove without a Mac: the pure dedupe order
computation, the dedupe validation rules (file and in-memory), the
CLI dedupe command on dump files, and the structural presence of
the AppleScript/run.sh guards (the handler exists, it retries with
a delay, rebuild returns a sentinel and duplicates nothing on a
delete failure, the delete call precedes the duplicate loop, the
mapping reader logs to the log file only). What they CANNOT prove:
that the AppleScript handlers actually behave on a Mac (no
osascript, no Music here). The handlers themselves are unproven
until the BRIDGE-SAFETY.md throwaway procedure passes on a Mac,
and these tests say so instead of pretending otherwise.
"""

from __future__ import annotations

import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.cli import main as cli_main
from seter_shuffle.order_direction import dedupe_ids
from seter_shuffle.validate import validate_order_file, validate_order_text

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "bridge"
RUN_SH = (ROOT / "run.sh").read_text(encoding="utf-8")


def _track(pid: str) -> dict:
    return {
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


def _write_dump(directory: Path, ids: list[str]) -> Path:
    path = directory / "library.json"
    path.write_text(
        json.dumps({"tracks": [_track(pid) for pid in ids]}),
        encoding="utf-8",
    )
    return path


class DedupeIdsTests(unittest.TestCase):
    def test_keeps_first_occurrence_order(self):
        self.assertEqual(
            dedupe_ids(["A", "B", "A", "C", "B", "D"]),
            ["A", "B", "C", "D"],
        )

    def test_no_duplicates_is_identity(self):
        ids = ["A", "B", "C"]
        self.assertEqual(dedupe_ids(ids), ids)

    def test_empty(self):
        self.assertEqual(dedupe_ids([]), [])

    def test_all_same(self):
        self.assertEqual(dedupe_ids(["X", "X", "X"]), ["X"])

    def test_input_not_mutated(self):
        ids = ["B", "A", "B"]
        dedupe_ids(ids)
        self.assertEqual(ids, ["B", "A", "B"])

    def test_reversed_doubled_playlist(self):
        # The 2026-10-29 failure shape: reverse(B) twice. Dedupe
        # yields unique songs in reversed order, NOT the backup
        # order: a backup-order restore is a separate step.
        backup = ["B49A108A0E5553DB", "X", "Y", "54BC5E32EB0D0F8E"]
        doubled = backup[::-1] + backup[::-1]
        self.assertEqual(dedupe_ids(doubled), backup[::-1])
        self.assertNotEqual(dedupe_ids(doubled), backup)


class DedupeValidationTests(unittest.TestCase):
    def test_valid_dedupe_order(self):
        validate_order_text(
            ["A", "B", "C"], {"A", "B", "C"}, mode="dedupe"
        )

    def test_dedupe_order_may_reorder(self):
        # Dedupe preserves first-occurrence order, which need not
        # be any canonical order; validation must accept any
        # permutation of the unique set.
        validate_order_text(
            ["C", "A", "B"], {"A", "B", "C"}, mode="dedupe"
        )

    def test_dedupe_order_with_repeat_refused(self):
        with self.assertRaises(ValueError):
            validate_order_text(
                ["A", "B", "A"], {"A", "B"}, mode="dedupe"
            )

    def test_dedupe_order_dropping_a_song_refused(self):
        with self.assertRaises(ValueError):
            validate_order_text(
                ["A", "B"], {"A", "B", "C"}, mode="dedupe"
            )

    def test_dedupe_order_with_invented_id_refused(self):
        with self.assertRaises(ValueError):
            validate_order_text(
                ["A", "B", "ZZZ"], {"A", "B"}, mode="dedupe"
            )

    def test_dedupe_order_empty_refused(self):
        with self.assertRaises(ValueError):
            validate_order_text([], {"A"}, mode="dedupe")

    def test_dedupe_order_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            dump = _write_dump(directory, ["A", "B", "A", "C"])
            order_txt = directory / "order.txt"
            order_txt.write_text("A\nB\nC\n", encoding="utf-8")
            order_json = directory / "order.json"
            order_json.write_text(
                json.dumps({"ids": ["A", "B", "C"], "count": 3}),
                encoding="utf-8",
            )
            self.assertEqual(
                validate_order_file(
                    dump, order_txt, order_json_path=order_json, mode="dedupe"
                ),
                ["A", "B", "C"],
            )

    def test_dedupe_order_file_with_repeat_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            dump = _write_dump(directory, ["A", "B", "A"])
            order_txt = directory / "order.txt"
            order_txt.write_text("A\nB\nA\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                validate_order_file(dump, order_txt, mode="dedupe")


class CliDedupeTests(unittest.TestCase):
    def test_cli_dedupe_writes_first_occurrence_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            dump = _write_dump(directory, ["B", "A", "B", "C", "A"])
            out = directory / "order.json"
            order_txt = directory / "order.txt"
            rc = cli_main(
                [
                    "dedupe",
                    "--library", str(dump),
                    "--out", str(out),
                    "--order-txt", str(order_txt),
                    "--quiet",
                ]
            )
            self.assertEqual(rc, 0)
            self.assertEqual(
                order_txt.read_text(encoding="utf-8"), "B\nA\nC\n"
            )
            self.assertEqual(json.loads(out.read_text())["ids"], ["B", "A", "C"])

    def test_cli_dedupe_leaves_dump_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            dump = _write_dump(directory, ["A", "B", "A"])
            before = dump.read_bytes()
            cli_main(
                [
                    "dedupe",
                    "--library", str(dump),
                    "--out", str(directory / "o.json"),
                    "--order-txt", str(directory / "o.txt"),
                    "--quiet",
                ]
            )
            self.assertEqual(dump.read_bytes(), before)

    def test_cli_dedupe_empty_playlist_returns_nonzero(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            dump = _write_dump(directory, [])
            rc = cli_main(
                [
                    "dedupe",
                    "--library", str(dump),
                    "--out", str(directory / "o.json"),
                    "--order-txt", str(directory / "o.txt"),
                    "--quiet",
                ]
            )
            self.assertNotEqual(rc, 0)


def _read_bridge(name: str) -> str:
    return (BRIDGE / name).read_text(encoding="utf-8")


def _handler_body(script: str, handler: str) -> str:
    """Text of one AppleScript handler (from its `on` line to the
    next `end <handler>`), for structural checks only."""
    start = script.index(f"on {handler}(")
    end = script.index(f"end {handler}", start)
    return script[start:end]


class DeleteEmptyStructuralTests(unittest.TestCase):
    SCRIPTS = [
        "apply-order.applescript",
        "undo.applescript",
        "restore-original.applescript",
        "sort-probe.applescript",
    ]

    def test_delete_empty_handler_present_in_every_rebuild_script(self):
        for name in self.SCRIPTS:
            script = _read_bridge(name)
            self.assertIn("on deletePlaylistSongs(pl)", script, name)
            body = _handler_body(script, "deletePlaylistSongs")
            # Bounded retries with a settle delay: the lag guard.
            self.assertIn("repeat with attempt from 1 to 5", body, name)
            self.assertIn("delay 5", body, name)
            # The re-read is the only evidence trusted: count of
            # song entries only, never the delete event's success.
            self.assertIn(
                "count of (every track of pl whose media kind is song)",
                body,
                name,
            )
            self.assertIn("if remaining is 0 then return true", body, name)
            # Never throws: a failed read is a failed gate, not an
            # exception that skips the check.
            self.assertIn("set remaining to -1", body, name)

    def test_rebuild_verifies_empty_before_duplicating(self):
        for name in self.SCRIPTS:
            script = _read_bridge(name)
            handler = "rebuildList" if "rebuildList" in script else "rebuild"
            body = _handler_body(script, handler)
            delete_pos = body.index("deletePlaylistSongs")
            duplicate_pos = body.index("duplicate sourceTrack to pl")
            self.assertLess(
                delete_pos, duplicate_pos,
                f"{name}: delete-empty check must precede the duplicate loop",
            )
            self.assertIn('return {"delete-not-empty"}', body, name)
            self.assertIn("if not emptied then", body, name)

    def test_delete_failure_is_handled_not_swallowed(self):
        # Every caller that rebuilds must name the delete failure
        # distinctly, not report it as "songs not found".
        for name in [
            "apply-order.applescript",
            "undo.applescript",
            "restore-original.applescript",
            "sort-probe.applescript",
        ]:
            script = _read_bridge(name)
            self.assertIn("delete-not-empty", script, name)
            self.assertIn("delete did not take effect", script, name)

    def test_bulk_reads_use_generous_timeout(self):
        for name in self.SCRIPTS:
            script = _read_bridge(name)
            body = _handler_body(script, "playlistIDs")
            self.assertIn("with timeout of 3600 seconds", body, name)


class RunnerStructuralTests(unittest.TestCase):
    def test_mapping_reader_logs_to_file_only(self):
        # Regression test for mode 31: mapping_for_build runs inside
        # $(...), so any log() call (tee to stdout) would pollute
        # the captured mapping and make the bridge refuse it.
        body = RUN_SH.split("mapping_for_build() {", 1)[1]
        body = body.split("\n}\n", 1)[0]
        self.assertNotIn("\n    log ", body)
        self.assertNotIn("\n  log ", body)
        self.assertIn("logfile", body)

    def test_dedupe_command_wired(self):
        self.assertIn("dedupe|restore|probe", RUN_SH)
        self.assertIn('"$CMD" = "dedupe"', RUN_SH)
        self.assertIn("seter_shuffle.cli dedupe", RUN_SH)
        self.assertIn('apply_order "$TARGET_PLAYLIST" "dedupe"', RUN_SH)
        # No-duplicate playlists skip the rebuild entirely.
        self.assertIn('if [ "$order_count" = "$dump_count" ]', RUN_SH)

    def test_per_run_backup_chain(self):
        # A failed run must never overwrite the main backup: the
        # apply writes to a per-run file, installed only on success.
        self.assertIn(".run-$(date +%Y%m%d-%H%M%S)-$$", RUN_SH)
        self.assertIn('cp "$run_backup" "$backup"', RUN_SH)
        self.assertIn('cp "$backup" "$backup.prev"', RUN_SH)
        self.assertIn("backup-*.run-*.txt", RUN_SH)
        # Failure path restores from the per-run snapshot and says
        # the main backup was not overwritten.
        self.assertIn("was NOT overwritten by this failed run", RUN_SH)

    def test_sortprobe_failure_deletes_mapping(self):
        # Since .5 the mapping is per-target: a failed probe deletes
        # only that target's mapping file, never a shared one.
        self.assertIn('rm -f "$MAP_FILE"', RUN_SH)

    def test_restore_command_exists_and_gates_on_backup(self):
        self.assertIn('"$CMD" = "restore"', RUN_SH)
        self.assertIn("restore-original.applescript", RUN_SH)
        self.assertIn('MAPPING="$(mapping_for_build "$PLAYLIST")"', RUN_SH)

    def test_undo_refuses_without_backup_file(self):
        self.assertIn('if [ ! -f "$BACKUP" ]', RUN_SH)
        self.assertIn("no backup file at $BACKUP", RUN_SH)


if __name__ == "__main__":
    unittest.main()
