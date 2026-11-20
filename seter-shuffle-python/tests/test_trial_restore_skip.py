"""Trial-dedupe redundant-undo skip (v3.0.7).

Regression for the 2026-10-29 21:01 trial-dedupe: apply-order
failed under forward, its internal restore succeeded, run.sh
ran undo anyway (3 more rebuilds of the same snapshot), and
undo's "restored to pre-undo state" exit was read as a
critical restore failure, so the trial stopped at 1612
without ever trying reversed.

The fix is a log-based skip in run.sh: after a failed apply,
if the lines since that apply's STEP line contain
"restored from backup" and no "CRITICAL", the playlist is
already back at the per-run snapshot and undo is skipped.
A CRITICAL apply must NOT skip, because then the playlist
is not known to be back at the snapshot.
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

RUN_SH = Path(__file__).resolve().parent.parent / "run.sh"


def skip_applies(log_text):
    """Replicate run.sh's skip condition on a synthetic log."""
    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write(log_text)
        path = f.name
    script = (
        'apply_step_line="$(grep -n "STEP: apply order to T" "%s" | tail -n 1 | cut -d: -f1)"; '
        'if [ -n "$apply_step_line" ] && tail -n +"$apply_step_line" "%s" | grep -q "restored from backup" '
        '&& ! tail -n +"$apply_step_line" "%s" | grep -q "CRITICAL"; then exit 0; else exit 1; fi'
        % (path, path, path)
    )
    return subprocess.run(["bash", "-c", script]).returncode == 0


class TestTrialRestoreSkip(unittest.TestCase):
    def test_run_sh_contains_skip(self):
        text = RUN_SH.read_text()
        self.assertIn("skipping the redundant undo restore (v3.0.7)", text)
        self.assertIn('grep -q "restored from backup"', text)
        self.assertIn('grep -q "CRITICAL"', text)

    def test_restored_apply_skips(self):
        log = (
            "2026-10-29 21:01:14 STEP: apply order to T\n"
            "apply-order: verification failed for \"T\" (final song order does not match "
            'the desired order under mapping forward); playlist restored from backup at /tmp/x.txt. (1)\n'
            "2026-10-29 21:05:23 GATE FAILED: apply order to T\n"
        )
        self.assertTrue(skip_applies(log))

    def test_critical_apply_does_not_skip(self):
        log = (
            "2026-10-29 21:01:14 STEP: apply order to T\n"
            "apply-order: CRITICAL: build/verification failed AND restore failed under "
            'both mappings for "T"; playlist may be partial. (1)\n'
            "2026-10-29 21:05:23 GATE FAILED: apply order to T\n"
        )
        self.assertFalse(skip_applies(log))

    def test_older_run_cannot_false_positive(self):
        # An old "restored from backup" line before this apply's STEP line
        # must not trigger the skip for the new apply.
        log = (
            "2026-10-29 20:00:00 STEP: apply order to T\n"
            "apply-order: verification failed; playlist restored from backup at /tmp/old.txt. (1)\n"
            "2026-10-29 21:01:14 STEP: apply order to T\n"
            "apply-order: some other failure, no restore claimed. (1)\n"
        )
        self.assertFalse(skip_applies(log))


if __name__ == "__main__":
    unittest.main()
