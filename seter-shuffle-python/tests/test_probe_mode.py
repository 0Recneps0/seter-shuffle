"""Tests for the probe-driven order-direction fix (2026-10-28 failure).

Background: the .4 bridge failed on a real 806-song playlist because
duplicating tracks into a playlist can land them in reverse order on
that Mac (or the every-track read is reversed; the backup files alone
cannot distinguish the two). The fix is a probe that measures the
direction on the Mac and a mode that every build and restore then
follows. These tests cover everything about that fix that CAN be
proven without a Mac: the pure mode formulas, the multiplicity-aware
validation, and the probe-output parsing run.sh uses. The AppleScript
handlers themselves cannot run here (no osascript, no Music); the
structural tests at the end only prove the handlers exist and name
the same modes, and BRIDGE-SAFETY.md says plainly that the bridge is
still unproven until the throwaway procedure passes on a Mac.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.order_direction import (
    build_for_apply,
    build_for_restore,
    display_order_for_snapshot,
    expected_for_apply,
    expected_for_restore,
    parse_mode,
)
from seter_shuffle.tracks import load_library
from seter_shuffle.validate import validate_order_file, validate_order_text

ROOT = Path(__file__).resolve().parents[1]


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


class ModeFormulaTests(unittest.TestCase):
    def test_forward_is_identity(self):
        order = ["A", "B", "C"]
        self.assertEqual(build_for_apply(order, "forward"), ["A", "B", "C"])
        self.assertEqual(expected_for_apply(order, "forward"), ["A", "B", "C"])
        self.assertEqual(build_for_restore(order, "forward"), ["A", "B", "C"])
        self.assertEqual(expected_for_restore(order, "forward"), ["A", "B", "C"])
        self.assertEqual(display_order_for_snapshot(order, "forward"), ["A", "B", "C"])

    def test_insert_reversed_flips_the_build_only(self):
        order = ["A", "B", "C"]
        # Duplicating reversed lands forwards, so the list read afterwards
        # equals the wanted order, not its reverse.
        self.assertEqual(build_for_apply(order, "insert-reversed"), ["C", "B", "A"])
        self.assertEqual(expected_for_apply(order, "insert-reversed"), ["A", "B", "C"])

    def test_read_reversed_flips_the_expectation_only(self):
        order = ["A", "B", "C"]
        # Duplicating in order lands the display correctly, but the
        # list read comes back reversed, so that is what verify must
        # expect.
        self.assertEqual(build_for_apply(order, "read-reversed"), ["A", "B", "C"])
        self.assertEqual(expected_for_apply(order, "read-reversed"), ["C", "B", "A"])

    def test_restore_build_and_expectation_in_every_mode(self):
        # A restore always verifies against the snapshot itself, and
        # always duplicates the snapshot under "forward" and its
        # reverse under either reversed mode. Worked through in
        # order_direction.py: under insert-reversed the insertion
        # flips reverse(T) back to T; under read-reversed the append
        # lands reverse(T) as the display, whose list read is T.
        snap = ["X", "Y", "Z"]
        for mode, build in (
            ("forward", ["X", "Y", "Z"]),
            ("insert-reversed", ["Z", "Y", "X"]),
            ("read-reversed", ["Z", "Y", "X"]),
        ):
            self.assertEqual(build_for_restore(snap, mode), build)
            self.assertEqual(expected_for_restore(snap, mode), snap)

    def test_restore_display_order_behind_a_snapshot(self):
        snap = ["X", "Y", "Z"]
        self.assertEqual(display_order_for_snapshot(snap, "forward"), snap)
        self.assertEqual(display_order_for_snapshot(snap, "insert-reversed"), snap)
        # Under read-reversed the snapshot IS the reverse of the display.
        self.assertEqual(display_order_for_snapshot(snap, "read-reversed"), ["Z", "Y", "X"])

    def test_empty_and_single_and_duplicates_are_preserved(self):
        for order in ([], ["A"], ["A", "A", "B"]):
            for mode in ("forward", "insert-reversed", "read-reversed"):
                self.assertEqual(len(build_for_apply(order, mode)), len(order))
                self.assertEqual(len(expected_for_apply(order, mode)), len(order))
                self.assertEqual(len(build_for_restore(order, mode)), len(order))

    def test_inputs_are_not_mutated(self):
        order = ["A", "B", "C"]
        build_for_apply(order, "insert-reversed")
        expected_for_apply(order, "read-reversed")
        build_for_restore(order, "read-reversed")
        self.assertEqual(order, ["A", "B", "C"])

    def test_unknown_mode_is_refused(self):
        for fn in (build_for_apply, expected_for_apply, build_for_restore,
                   expected_for_restore, display_order_for_snapshot, parse_mode):
            with self.assertRaises(ValueError):
                if fn is parse_mode:
                    fn("sideways")
                else:
                    fn(["A"], "sideways")


class DuplicateEntryValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _write(self, name: str, text: str) -> Path:
        path = self.dir / name
        path.write_text(text, encoding="utf-8")
        return path

    def test_load_library_strict_by_default_allows_for_playlist_shuffle(self):
        bad = self._write(
            "dup.json",
            json.dumps({"tracks": [_track("X"), _track("X")]}),
        )
        with self.assertRaises(ValueError):
            load_library(bad)
        tracks = load_library(bad, allow_duplicates=True)
        self.assertEqual([t.persistent_id for t in tracks], ["X", "X"])

    def test_shuffle_preserves_duplicate_entries_exactly(self):
        lib = self._write(
            "lib.json",
            json.dumps({"tracks": [_track("A"), _track("B"), _track("A")]}),
        )
        # Reordering the duplicate entry is fine; dropping one copy
        # of it, or inventing a third, is not.
        keep = self._write("order.txt", "A\nB\nA\n")
        self.assertEqual(
            validate_order_file(lib, keep, mode="shuffle"), ["A", "B", "A"]
        )
        drop = self._write("order-drop.txt", "A\nB\n")
        with self.assertRaises(ValueError):
            validate_order_file(lib, drop, mode="shuffle")
        invent = self._write("order-invent.txt", "A\nA\nA\nB\n")
        with self.assertRaises(ValueError):
            validate_order_file(lib, invent, mode="shuffle")

    def test_whole_library_shuffle_still_refuses_a_repeat(self):
        lib = self._write(
            "lib2.json",
            json.dumps({"tracks": [_track("A"), _track("B")]}),
        )
        bad = self._write("order2.txt", "A\nA\n")
        with self.assertRaises(ValueError):
            validate_order_file(lib, bad, mode="shuffle")

    def test_in_memory_multiset_check(self):
        counts = {"A": 2, "B": 1}
        validate_order_text(["B", "A", "A"], {"A", "B"}, mode="shuffle",
                            library_counts=counts)
        with self.assertRaises(ValueError):
            validate_order_text(["A", "B"], {"A", "B"}, mode="shuffle",
                                library_counts=counts)

    def test_cli_playlist_shuffle_keeps_duplicates_with_flag(self):
        lib = self.dir / "lib3.json"
        lib.write_text(
            json.dumps({"tracks": [_track("A"), _track("B"), _track("A")]}),
            encoding="utf-8",
        )
        out = self.dir / "order.json"
        txt = self.dir / "order.txt"
        result = subprocess.run(
            [sys.executable, "-m", "seter_shuffle.cli", "shuffle",
             "--library", str(lib), "--seed", "3", "--allow-duplicates",
             "--out", str(out), "--order-txt", str(txt)],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        ids = txt.read_text(encoding="utf-8").splitlines()
        self.assertEqual(sorted(ids), ["A", "A", "B"])
        # And the same shuffle without the flag still fails closed.
        result2 = subprocess.run(
            [sys.executable, "-m", "seter_shuffle.cli", "shuffle",
             "--library", str(lib), "--seed", "3",
             "--out", str(out), "--order-txt", str(txt)],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        self.assertNotEqual(result2.returncode, 0)


class ProbeParsingTests(unittest.TestCase):
    def test_run_sh_verdict_extraction(self):
        # run.sh extracts the verdict with: grep '^PROBE_VERDICT: ' |
        # sed 's/^PROBE_VERDICT: //'. Run that exact pipeline on a
        # sample probe block and confirm each verdict comes out clean.
        sample = (
            "PROBE_PICKED: AAA BBB CCC\n"
            "PROBE_LIST: CCC BBB AAA\n"
            "PROBE_INDEX_ORDER: CCC BBB AAA\n"
            "PROBE_POS_FIRST: CCC\n"
            "PROBE_POS_LAST: AAA\n"
            "PROBE_VERDICT: insert-reversed\n"
            "PROBE_CLEANUP_OK\n"
        )
        result = subprocess.run(
            "grep '^PROBE_VERDICT: ' | sed 's/^PROBE_VERDICT: //'",
            shell=True, input=sample, capture_output=True, text=True,
        )
        self.assertEqual(result.stdout.strip(), "insert-reversed")

    def test_probe_verdict_values_are_the_three_modes(self):
        for verdict in ("forward", "insert-reversed", "read-reversed"):
            self.assertEqual(parse_mode(verdict), verdict)


class BridgeStructureTests(unittest.TestCase):
    """Presence checks only: the AppleScript cannot run here.

    These assert the mode handlers and probe script exist and name the
    same three modes as order_direction.py. They prove the wiring was
    written, not that Music behaves; the Mac throwaway procedure in
    BRIDGE-SAFETY.md is what proves behaviour.
    """

    def _bridge_text(self, name: str) -> str:
        return (ROOT / "bridge" / name).read_text(encoding="utf-8")

    def test_probe_script_exists_and_reports_a_verdict(self):
        text = self._bridge_text("probe-order.applescript")
        self.assertIn("PROBE_VERDICT:", text)
        self.assertIn("PROBE_CLEANUP_OK", text)
        self.assertIn("SeTeR Shuffle Probe", text)

    def test_apply_and_undo_are_mode_aware(self):
        for name in ("apply-order.applescript", "undo.applescript"):
            text = self._bridge_text(name)
            self.assertIn("insert-reversed", text, name)
            self.assertIn("read-reversed", text, name)
            self.assertIn("buildForApply", text, name)
            self.assertIn("buildForRestore", text, name)
            self.assertIn("expectedForApply", text, name)
            self.assertIn("expectedForRestore", text, name)

    def test_restore_original_is_mode_aware_with_explicit_flip(self):
        text = self._bridge_text("restore-original.applescript")
        self.assertIn("insert-reversed", text)
        self.assertIn("read-reversed", text)
        # The old silent flip is gone from the default path; it survives
        # only as an explicit, documented last-resort mode.
        self.assertIn("flip", text)

    def test_run_sh_probes_before_every_apply_and_undo(self):
        text = (ROOT / "run.sh").read_text(encoding="utf-8")
        self.assertIn("probe", text)
        self.assertIn("probe_mode", text)
        self.assertIn("probe-order.applescript", text)
