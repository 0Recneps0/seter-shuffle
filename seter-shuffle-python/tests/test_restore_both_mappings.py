"""Tests for v3.0.5: restores try BOTH mappings before CRITICAL.

The trap, proven on Spencer's Mac 2026-10-29 18:59-19:05 PT:
trial-dedupe tried forward first on "My New Sandwich
Recipe" (1612 entries, 806 unique). The playlist's true
mapping is reversed, so the forward dedupe build
verified-failed, as it should. Then apply-order's
internal restore rebuilt the pre-dedupe snapshot with
the SAME forward mapping, so it verified-failed too and
declared CRITICAL, and the run.sh undo restore failed
the same way. The pre-undo snapshot proved all 1612
entries were present, in the exact reverse of the
snapshot, and a read-only diagnostic at 19:08 PT proved
the current list-read order is exactly the pre-dedupe
snapshot order. No songs were lost; the trap was that
a restore under a wrong mapping cannot verify, by the
same mechanism as the build failure.

The fix: every restore tries both mappings, given first
then opposite, each verified against the snapshot it
returns to, and only declares CRITICAL if neither
verifies. This is a RESTORE retry, not a build flip: a
failed build still exits non-zero and records nothing,
and the opposite mapping is never used to land a
desired order.

AppleScript itself cannot run here, so the bridge
scripts are tested structurally (handler presence, all
restore call sites using the both-mappings handler, no
opposite-mapping use inside a build handler), and the
run.sh trial behaviour is tested with a fake `osascript`
standing in for the bridge, as in test_trial_dedupe.py:
a fake undo failure stands in for a restore failing
under both mappings inside undo, and a fake undo
success stands in for a restore succeeding under
either mapping.
"""

from __future__ import annotations

import hashlib
import os
import re
import shlex
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = "My New Sandwich Recipe"

FAKE_OSASCRIPT = """#!/usr/bin/env python3
import json
import os
import shlex
import sys
from pathlib import Path

if len(sys.argv) > 1 and sys.argv[1] == "-e":
    sys.exit(0)
script = Path(sys.argv[1]).name
calls = Path(os.environ["FAKE_CALLS"])
with calls.open("a") as handle:
    handle.write(script + " " + " ".join(shlex.quote(a) for a in sys.argv[2:]) + "\\n")
if script == "dump-library.applescript":
    dump = Path(sys.argv[2])
    ids = os.environ.get("FAKE_DUMP_IDS", "A B A C B").split()
    tracks = [
        {
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
        for pid in ids
    ]
    dump.write_text(json.dumps({"tracks": tracks}), encoding="utf-8")
    sys.exit(0)
if script == "apply-order.applescript":
    run_backup = Path(sys.argv[4])
    mapping = sys.argv[5]
    run_backup.write_text(
        "\\n".join(os.environ.get("FAKE_DUMP_IDS", "A B A C B").split()) + "\\n",
        encoding="utf-8",
    )
    # Presence mode (v3.0.8): succeeds regardless of mapping.
    if sys.argv[-1] == "presence":
        sys.exit(1 if os.environ.get("FAKE_APPLY_FAIL") == "1" else 0)
    if mapping == os.environ.get("FAKE_WINNING_MAPPING", "reversed"):
        sys.exit(0)
    sys.exit(1)
if script == "dedupe-in-place.applescript":
    # Args: target, order-txt, delete-indices-txt, run-backup.
    # The bridge writes its verified pre-change snapshot to
    # the run-backup before deleting; the fake stands in for
    # that write and for a presence-verified delete (0 rebuilds).
    run_backup = Path(sys.argv[5])
    run_backup.write_text(
        "\\n".join(os.environ.get("FAKE_DUMP_IDS", "A B A C B").split()) + "\\n",
        encoding="utf-8",
    )
    sys.exit(1 if os.environ.get("FAKE_APPLY_FAIL") == "1" else 0)
if script == "undo.applescript":
    # Exit 1 stands in for the undo script's internal restore
    # failing under BOTH mappings; exit 0 stands in for a
    # restore succeeding under either mapping.
    sys.exit(1 if os.environ.get("FAKE_UNDO_FAIL") == "1" else 0)
sys.exit(0)
"""


def mapping_file(state: Path, name: str) -> Path:
    safe = name.replace("\n", "_").replace("\r", "_").replace(" ", "_").replace("/", "_")
    digest = hashlib.sha256(name.encode()).hexdigest()[:12]
    return state / f"sort-mapping-{safe}-{digest}.txt"


def backup_file(state: Path, name: str) -> Path:
    safe = name.replace("\n", "_").replace("\r", "_").replace(" ", "_").replace("/", "_")
    digest = hashlib.sha256(name.encode()).hexdigest()[:12]
    return state / f"backup-{safe}-{digest}.txt"


def bridge(name: str) -> str:
    return (ROOT / "bridge" / name).read_text(encoding="utf-8")


def handler(text: str, name: str) -> str:
    match = re.search(
        r"on %s\b.*?^end %s" % (re.escape(name), re.escape(name)),
        text,
        re.S | re.M,
    )
    assert match is not None, f"handler {name} not found"
    return match.group(0)


class RestoreBothMappingsHarness(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.bindir = self.base / "bin"
        self.bindir.mkdir()
        stub = self.bindir / "osascript"
        stub.write_text(FAKE_OSASCRIPT, encoding="utf-8")
        stub.chmod(0o755)
        self.calls = self.base / "calls.log"
        self.env = dict(os.environ)
        self.env["HOME"] = str(self.home)
        self.env["PATH"] = str(self.bindir) + os.pathsep + os.environ["PATH"]
        self.env["FAKE_CALLS"] = str(self.calls)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def state(self) -> Path:
        return self.home / "Library" / "Logs" / "seter-shuffle-python"

    def run_dedupe(self, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
        env = dict(self.env)
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            ["bash", str(ROOT / "run.sh"), "dedupe", TARGET],
            capture_output=True,
            text=True,
            env=env,
            timeout=60,
        )

    def apply_mappings(self) -> list[str]:
        if not self.calls.exists():
            return []
        mappings = []
        for line in self.calls.read_text(encoding="utf-8").splitlines():
            parts = shlex.split(line)
            if parts and parts[0] == "apply-order.applescript":
                # 8 apply arguments: mapping is 5th from the end.
                mappings.append(parts[-5])
        return mappings

    def dedupe_in_place_calls(self) -> list[str]:
        if not self.calls.exists():
            return []
        return [
            line for line in self.calls.read_text(encoding="utf-8").splitlines()
            if line.startswith("dedupe-in-place.applescript")
        ]

    def test_dedupe_presence_succeeds_without_trial(self) -> None:
        # v3.0.8: dedupe no longer trials, so a reversed true
        # mapping does not produce a forward failure, an undo
        # restore, or a critical stop: one presence apply lands
        # the song set and records no mapping.
        result = self.run_dedupe({"FAKE_WINNING_MAPPING": "reversed"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.apply_mappings(), [])
        self.assertEqual(len(self.dedupe_in_place_calls()), 1)
        self.assertFalse(mapping_file(self.state(), TARGET).exists())

    def test_dedupe_presence_failure_records_nothing(self) -> None:
        result = self.run_dedupe({"FAKE_APPLY_FAIL": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.apply_mappings(), [])
        self.assertEqual(len(self.dedupe_in_place_calls()), 1)
        self.assertFalse(mapping_file(self.state(), TARGET).exists())
        self.assertFalse(
            backup_file(self.state(), TARGET).exists(),
            "a failed dedupe must not install a main backup",
        )


class BridgeRestoreStructuralTests(unittest.TestCase):
    def test_apply_order_restores_try_both_mappings(self) -> None:
        text = bridge("apply-order.applescript")
        self.assertIn("on tryRestoreBothMappings", text)
        self.assertIn("on oppositeMapping", text)
        # Every restore call site uses the both-mappings handler:
        # the only remaining tryRestoreMapping mentions are its
        # definition, its end line, and the two calls inside
        # tryRestoreBothMappings; all three restore sites call
        # the both-mappings handler.
        self.assertEqual(text.count("tryRestoreMapping"), 4)
        self.assertEqual(text.count("tryRestoreBothMappings(destPl"), 3)
        self.assertIn("restore failed under both mappings", text)
        # The build handler itself never retries the opposite
        # mapping: that would be a build flip, not a restore.
        build = handler(text, "buildAndVerifyMapping")
        self.assertNotIn("opposite", build)
        self.assertIn("never retried with the opposite mapping", text)

    def test_undo_pre_undo_restore_tries_both_mappings(self) -> None:
        text = bridge("undo.applescript")
        self.assertIn("on tryRestoreBothMappings", text)
        self.assertIn("on oppositeMapping", text)
        self.assertEqual(text.count("tryRestoreMapping"), 4)
        self.assertEqual(text.count("tryRestoreBothMappings(destPl"), 2)
        self.assertIn("pre-undo restore failed under both mappings", text)
        build = handler(text, "buildAndVerifyMapping")
        self.assertNotIn("opposite", build)

    def test_restore_original_put_back_tries_both_mappings(self) -> None:
        text = bridge("restore-original.applescript")
        self.assertIn("on tryPutBackBothMappings", text)
        self.assertIn("on oppositeMapping", text)
        self.assertIn("could not be put back under either mapping", text)
        # The old single-mapping put-back (rebuild the snapshot
        # under the given mapping only) must be gone.
        self.assertNotIn("buildForMapping(currentIDs", text)

    def test_run_sh_trial_stop_means_both_restore_mappings_failed(self) -> None:
        text = (ROOT / "run.sh").read_text(encoding="utf-8")
        self.assertIn("restore failed under both mappings", text)
        self.assertIn("undo itself tries both mappings", text)
        self.assertIn("both were tried, each verified", text)

    def test_no_new_array_expansion(self) -> None:
        for name in ("run.sh", "daily.sh"):
            text = (ROOT / name).read_text(encoding="utf-8")
            code = "\n".join(
                line for line in text.splitlines() if not line.lstrip().startswith("#")
            )
            for match in re.finditer(r"\$\{(\w+)\[@\]\}", code):
                self.assertEqual(
                    match.group(1),
                    "apply_args",
                    f"{name}: unexpected [@] expansion {match.group(0)}",
                )


if __name__ == "__main__":
    unittest.main()
