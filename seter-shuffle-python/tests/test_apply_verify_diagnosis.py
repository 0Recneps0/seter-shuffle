"""Tests for the apply verify-failure diagnosis (2026-11-21 experimental).

When a build fails verification, bridge/apply-order.applescript now
re-reads the playlist once and reports whether it landed in the
EXACT REVERSE of the desired order. That pattern is the signature
of a flipped recorded mapping (the 2026-11-20 18:40 Flow failure:
built under "forward", landed exactly reversed, and a fresh
self-probe then measured "reversed"), and the error then says so
and names ./run.sh selfprobe for the target.

What CAN be proven here: the classification the diagnosis relies
on (the Python mirror in seter_shuffle.order_direction, already
the authority the sort-probe shares with the bridge), and the
static shape of the AppleScript change (the diagnosis is computed
from a try-guarded re-read, the restore still precedes the error,
no build is retried under the opposite mapping). The AppleScript
itself cannot run here (no osascript, no Music), so its half is
documented in BRIDGE-SAFETY.md with a Mac verification procedure,
and is NOT faked into passing here.

Run from the project root:
    python3 -m unittest discover -s tests -v
"""

from __future__ import annotations

import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.order_direction import mapping_from_build_result

BRIDGE = Path(__file__).resolve().parents[1] / "bridge" / "apply-order.applescript"


def _handler_body(text: str, name: str) -> str:
    """AppleScript handler body between `on <name>` and its `end <name>`."""
    start = text.index(f"on {name}(")
    end = text.index(f"end {name}", start)
    return text[start:end]


def _nth_index(text: str, needle: str, n: int) -> int:
    """Index of the nth (1-based) occurrence of needle in text."""
    index = -1
    for _ in range(n):
        index = text.index(needle, index + 1)
    return index


class DiagnosisClassificationTests(unittest.TestCase):
    """The classification the bridge diagnosis mirrors.

    The bridge compares the landed list read against the desired
    order and its exact reverse; these are the same three outcomes
    the sort-probe measures, so a "reversed" landing under the
    recorded mapping means the recorded mapping is flipped.
    """

    def test_exact_reverse_landing_is_the_diagnosis_trigger(self):
        desired = ["A", "B", "C", "D"]
        self.assertEqual(
            mapping_from_build_result(desired, desired[::-1]), "reversed"
        )

    def test_exact_landing_is_not_a_diagnosis(self):
        desired = ["A", "B", "C", "D"]
        self.assertEqual(mapping_from_build_result(desired, desired), "forward")

    def test_scrambled_landing_is_not_a_diagnosis(self):
        desired = ["A", "B", "C", "D"]
        self.assertEqual(
            mapping_from_build_result(desired, ["B", "A", "D", "C"]), "other"
        )

    def test_partial_landing_is_not_a_diagnosis(self):
        desired = ["A", "B", "C", "D"]
        self.assertEqual(
            mapping_from_build_result(desired, ["D", "C", "B"]), "other"
        )


class BridgeDiagnosisTextTests(unittest.TestCase):
    """Static pins on the AppleScript diagnosis (see module docstring)."""

    def setUp(self) -> None:
        self.text = BRIDGE.read_text(encoding="utf-8")
        self.build_handler = _handler_body(self.text, "buildAndVerifyMapping")
        self.presence_handler = _handler_body(
            self.text, "buildAndVerifyPresence"
        )

    def test_every_build_return_carries_the_diagnosis_field(self):
        # Failed-songs, verified, and verify-failed returns alike:
        # a caller must be able to read the field on any result.
        self.assertEqual(self.build_handler.count("landedReversed:"), 3)
        self.assertIn(
            "{ok:false, failed:failedIDs, landedReversed:false}",
            self.build_handler,
        )
        self.assertIn(
            "{ok:true, failed:{}, landedReversed:false}", self.build_handler
        )
        self.assertIn(
            "{ok:false, failed:{}, landedReversed:landedReversed}",
            self.build_handler,
        )

    def test_diagnosis_reads_the_playlist_once_inside_try(self):
        # The diagnosis re-read must never turn a failed verify
        # into a different failure: a failed read leaves the
        # diagnosis off and the generic error stands.
        read_at = self.build_handler.index("set landedIDs to my playlistIDs(pl)")
        try_at = self.build_handler.index("try", read_at - 60)
        error_at = self.build_handler.index("on error", read_at)
        self.assertLess(try_at, read_at)
        self.assertLess(read_at, error_at)
        self.assertIn(
            "set landedReversed to my listsEqual(landedIDs, my reverseList(desiredIDs))",
            self.build_handler,
        )

    def test_presence_handler_returns_carry_the_field_too(self):
        # Uniform record shape, so the field is safe to read on
        # either build result; presence mode never sets it true.
        self.assertEqual(self.presence_handler.count("landedReversed:false"), 3)
        self.assertNotIn("landedReversed:true", self.presence_handler)

    def test_caller_names_the_reversed_landing_and_the_next_step(self):
        self.assertEqual(
            self.text.count("else if landedReversed of buildResult then"), 1
        )
        self.assertIn("EXACT REVERSE of the desired order", self.text)
        self.assertIn("Re-run ./run.sh selfprobe '", self.text)

    def test_restore_precedes_the_diagnosis_error(self):
        # The diagnosis changes only the error text: the playlist
        # is restored from backup before the error is raised.
        restore_at = _nth_index(
            self.text,
            "set restoreResult to my tryRestoreBothMappings(destPl, backupIDs, buildMapping)",
            2,
        )
        diagnosis_at = self.text.index("EXACT REVERSE of the desired order")
        self.assertLess(restore_at, diagnosis_at)

    def test_no_build_is_retried_under_the_opposite_mapping(self):
        # The failure path never calls the build handler again:
        # the diagnosis reports, it does not flip or retry.
        self.assertEqual(self.text.count("my buildAndVerifyMapping("), 2)

    def test_diagnosis_is_documented_as_diagnosis_not_flip(self):
        self.assertIn("landedReversed is a DIAGNOSIS only", self.text)
        self.assertIn("DIAGNOSIS, NOT A FLIP", self.text)


if __name__ == "__main__":
    unittest.main()
