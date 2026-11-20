"""Presence-only dedupe verify (v3.0.8).

Spencer said 2026-10-30 dedupe need not keep the original
order, so a dedupe apply verifies the landed song SET, not
the order: same count, every desired ID present. With unique
desired IDs (a dedupe order by construction), count plus
presence implies set equality: a leftover duplicate or an
extra song breaks the count, a missing song breaks presence.

Consequences asserted here:
- apply-order has a presence verify handler and a presence
  build handler, used only when the 8th argument is
  "presence"; restores still verify exactly.
- run.sh passes "presence" only for dedupe, "exact" else.
- The dedupe case calls apply_order_mapped directly with
  an arbitrary mapping and never calls trial-dedupe or
  record_trial_mapping: a presence success proves nothing
  about the sort, so no mapping may be recorded from it.
- The Python model of the presence rule: reversed order
  passes, a missing song fails, a leftover duplicate fails.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUN_TEXT = (ROOT / "run.sh").read_text()
BRIDGE_TEXT = (ROOT / "bridge" / "apply-order.applescript").read_text()


def presence_ok(actual, desired):
    if len(actual) != len(desired):
        return False
    return all(d in actual for d in desired)


class TestDedupePresence(unittest.TestCase):
    def test_bridge_has_presence_handlers(self):
        self.assertIn("on verifyPresence(pl, expectedIDs)", BRIDGE_TEXT)
        self.assertIn("on buildAndVerifyPresence(pl, desiredIDs, buildMapping)", BRIDGE_TEXT)
        self.assertIn('is "presence" then set verifyPresenceMode to true', BRIDGE_TEXT)

    def test_bridge_restores_still_exact(self):
        # Restores use the exact handlers, never presence.
        self.assertIn("tryRestoreBothMappings(destPl, backupIDs, buildMapping)", BRIDGE_TEXT)
        self.assertNotIn("verifyPresence(pl, backupIDs)", BRIDGE_TEXT)

    def test_run_passes_presence_only_for_dedupe(self):
        self.assertIn('if [ "$mode" = "dedupe" ]; then\n    verify_mode="presence"', RUN_TEXT)
        self.assertIn('verify_mode="exact"', RUN_TEXT)
        self.assertIn('"$verify_mode")', RUN_TEXT)

    def test_dedupe_case_needs_no_mapping_and_records_none(self):
        # v3.0.9: dedupe no longer applies at all; it deletes in
        # place, so the case calls dedupe_in_place, never
        # apply_order_mapped, trial-dedupe, or a mapping check.
        dedupe_block = RUN_TEXT.split('  dedupe)\n', 1)[1].split('    ;;\n', 1)[0]
        self.assertIn('dedupe_in_place "$TARGET_PLAYLIST"', dedupe_block)
        self.assertNotIn("dedupe_trial_apply", dedupe_block)
        self.assertNotIn("record_trial_mapping", dedupe_block)
        self.assertNotIn("mapping_is_ready", dedupe_block)
        self.assertNotIn('apply_order_mapped "$TARGET_PLAYLIST" "dedupe"', dedupe_block)

    def test_presence_model(self):
        desired = ["A", "B", "C"]
        self.assertTrue(presence_ok(["C", "B", "A"], desired))  # reversed passes
        self.assertTrue(presence_ok(["B", "A", "C"], desired))  # any order passes
        self.assertFalse(presence_ok(["C", "B"], desired))  # missing song
        self.assertFalse(presence_ok(["C", "B", "A", "A"], desired))  # leftover duplicate
        self.assertFalse(presence_ok(["C", "B", "X"], desired))  # wrong song


if __name__ == "__main__":
    unittest.main()
