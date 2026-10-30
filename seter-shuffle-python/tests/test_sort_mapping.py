"""Tests for the sort-matched build mapping model (2026-10-29).

Mirrors seter_shuffle/order_direction.py's mapping section, the
single source of truth shared with the AppleScript buildForMapping
handlers. The AppleScript itself cannot run here, so these tests
prove the formulas, not the bridge; the Mac throwaway procedure in
BRIDGE-SAFETY.md is what proves the bridge.

Deliberately NOT tested here: any classification based on the track
`index` property. The 2026-10-29 diagnostic on the real playlist
showed the list read reversed against the original backup while
the list's first track carried index 1, which kills index as a
manual-order reference (see order_direction.py). Index is a reported
diagnostic value only, never a classification input.
"""

import unittest

from seter_shuffle.order_direction import (
    build_for_mapping,
    expected_for_mapping,
    mapping_from_build_result,
    parse_mapping,
)


class TestMappingFromBuildResult(unittest.TestCase):
    def test_forward(self):
        self.assertEqual(
            mapping_from_build_result(["A", "B", "C"], ["A", "B", "C"]),
            "forward",
        )

    def test_reversed(self):
        self.assertEqual(
            mapping_from_build_result(["A", "B", "C"], ["C", "B", "A"]),
            "reversed",
        )

    def test_other_for_scrambled(self):
        self.assertEqual(
            mapping_from_build_result(["A", "B", "C", "D"], ["B", "A", "D", "C"]),
            "other",
        )

    def test_other_for_length_mismatch(self):
        self.assertEqual(
            mapping_from_build_result(["A", "B", "C"], ["A", "B"]),
            "other",
        )

    def test_rotate_probe_order_is_unambiguous(self):
        # The sort-probe builds a rotation of the current list. A
        # rotation is neither the list nor its reverse (for 5+
        # distinct songs), so forward/reversed/other are distinct.
        current = ["A", "B", "C", "D", "E"]
        build = current[1:] + current[:1]
        self.assertNotEqual(build, current)
        self.assertNotEqual(build, current[::-1])
        self.assertEqual(mapping_from_build_result(build, build), "forward")
        self.assertEqual(
            mapping_from_build_result(build, build[::-1]), "reversed"
        )

    def test_empty(self):
        self.assertEqual(mapping_from_build_result([], []), "forward")


class TestBuildForMapping(unittest.TestCase):
    def test_forward_build_is_desired(self):
        desired = ["A", "B", "C"]
        self.assertEqual(build_for_mapping(desired, "forward"), desired)
        self.assertEqual(desired, ["A", "B", "C"])  # input not mutated

    def test_reversed_build_is_reversed(self):
        self.assertEqual(
            build_for_mapping(["A", "B", "C"], "reversed"), ["C", "B", "A"]
        )

    def test_other_build_raises(self):
        with self.assertRaises(ValueError):
            build_for_mapping(["A", "B"], "other")

    def test_unknown_mapping_raises(self):
        with self.assertRaises(ValueError):
            build_for_mapping(["A"], "sideways")
        with self.assertRaises(ValueError):
            parse_mapping("insert-reversed")  # legacy probe mode, not a mapping

    def test_verify_expectation_is_desired_in_both_mappings(self):
        # Key invariant: verification always compares the list read
        # against the desired list-read order, never against the
        # duplicate order.
        for mapping in ("forward", "reversed"):
            self.assertEqual(
                expected_for_mapping(["A", "B", "C"], mapping),
                ["A", "B", "C"],
            )

    def test_verify_expectation_raises_for_other(self):
        with self.assertRaises(ValueError):
            expected_for_mapping(["A"], "other")

    def test_reversed_round_trip(self):
        # Simulate a descending-sorted display: duplicating
        # reverse(D) as manual order lands list read D, because the
        # sort reverses the manual order back.
        desired = ["S1", "S2", "S3", "S4"]
        manual = build_for_mapping(desired, "reversed")
        list_read_after_sort = manual[::-1]
        self.assertEqual(
            list_read_after_sort,
            expected_for_mapping(desired, "reversed"),
        )

    def test_restore_formula_with_real_backup_ends(self):
        # B = original backup order (ends only; the full list is
        # 806 IDs). A restore wants list read B again. Under a
        # reversed mapping it must duplicate reverse(B); under a
        # forward mapping it duplicates B.
        backup = ["B49A108A0E5553DB", "X", "Y", "54BC5E32EB0D0F8E"]
        self.assertEqual(build_for_mapping(backup, "forward"), backup)
        self.assertEqual(
            build_for_mapping(backup, "reversed"), backup[::-1]
        )
        # And the reversed build, reversed again by the sort, lands B.
        self.assertEqual(
            build_for_mapping(backup, "reversed")[::-1],
            expected_for_mapping(backup, "reversed"),
        )


if __name__ == "__main__":
    unittest.main()
