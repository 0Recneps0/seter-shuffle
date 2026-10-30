"""Tests for v3.0.4 trial-dedupe, superseded for the dedupe
path by v3.0.8 presence dedupe (see test_dedupe_presence.py):
dedupe no longer trials forward then reversed, because a
presence-verified apply lands the song set under either
mapping and records no mapping. The trial functions remain
in run.sh but are no longer called by the dedupe case, and
the harness below now tests the presence path instead.
The original trial-dedupe history is kept in this file's
git history and in the v3.0.4-3.0.7 release notes.

Tests for v3.0.4 trial-dedupe.

The deadlock, proven on Spencer's Mac 2026-10-29 18:44 PT: the
v3.0.3 menu auto self-probe on "My New Sandwich Recipe" refused
on duplicate entries (1612 entries, 806 unique), target untouched,
no dump or apply. Dedupe needs a mapping, and the rotation probe
cannot measure one on a doubled playlist. Trial-dedupe breaks
that deadlock WITHOUT weakening the probe: dedupe's desired
order is known in advance (first occurrence of each song), so
the runner tries it under mapping forward, verifies the list
read against it, and on failure restores from the snapshot and
tries reversed. Verify-after on the actual desired order is
the mapping oracle here, not a rotation classification, and
this path must never be borrowed back into the probe: the
probe's duplicate refusal is unchanged.

What is tested here, without a Mac (AppleScript itself cannot
run here, so a fake `osascript` written in Python stands in
for the bridge, and a stub `run.sh` stands in for daily.sh's
calls):
  * Dedupe with no mapping tries forward, then reversed, and
    records the winning mapping; the apply calls are in that
    order and no sort-probe call is made.
  * Dedupe with a forward win tries only forward.
  * Dedupe with a fresh mapping uses it directly, with no trial.
  * Dedupe on an already-clean playlist applies nothing and
    needs no mapping.
  * Dedupe where neither mapping verifies restores the
    pre-dedupe order, records no mapping, and installs no
    main backup.
  * Menu dedupe (choice 3) uses the trial path, not the
    mapping gate, on a doubled playlist.
  * daily.sh: a duplicate-only probe failure for the daily
    playlist triggers trial-dedupe and the run continues;
    a duplicate probe failure plus a failed dedupe stops the
    run before the Rediscover probe and any build.
  * Structural: the trial functions exist, the probe's
    duplicate refusal is unchanged, and no new bash 3.2
    empty-array expansion was introduced.
"""

from __future__ import annotations

import hashlib
import os
import re
import shlex
import shutil
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
# Shell-quote every argument: the apply call's lib-songs argument
# is empty for a playlist dump, and a plain space join would drop
# it, shifting every later argument's position in the log.
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
    # The apply script's pre-change snapshot: the doubled order.
    run_backup.write_text(
        "\\n".join(os.environ.get("FAKE_DUMP_IDS", "A B A C B").split()) + "\\n",
        encoding="utf-8",
    )
    # Verify-after simulation for exact mode: only the winning
    # mapping lands the deduped order, so only it exits 0.
    # Presence mode (v3.0.8, last argument "presence") lands
    # the song set under either mapping, so it exits 0
    # regardless of the winning mapping, unless forced to fail.
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
    sys.exit(0)
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


def read_fields(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        key, _, value = line.partition(": ")
        out[key] = value
    return out


class TrialDedupeHarness(unittest.TestCase):
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
                # Args after the (multi-word) target are order-txt,
                # run-backup, mapping, allow-dupes, lib-songs,
                # stamp, verify-mode, so the mapping is 5th from
                # the end (shlex preserves the empty lib-songs
                # argument).
                mappings.append(parts[-5])
        return mappings

    def dedupe_in_place_calls(self) -> list[str]:
        if not self.calls.exists():
            return []
        return [
            line for line in self.calls.read_text(encoding="utf-8").splitlines()
            if line.startswith("dedupe-in-place.applescript")
        ]

    def call_basenames(self) -> list[str]:
        if not self.calls.exists():
            return []
        return [shlex.split(line)[0] for line in self.calls.read_text(encoding="utf-8").splitlines()]

    def test_dedupe_presence_succeeds_single_apply_no_mapping(self) -> None:
        # v3.0.8: even when the true mapping is reversed, a
        # presence-verified dedupe succeeds on its single
        # forward apply and records NO mapping, because a
        # presence success proves nothing about the sort.
        result = self.run_dedupe({"FAKE_WINNING_MAPPING": "reversed"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.apply_mappings(), [])
        self.assertEqual(len(self.dedupe_in_place_calls()), 1)
        self.assertNotIn("sort-probe.applescript", self.call_basenames())
        self.assertFalse(mapping_file(self.state(), TARGET).exists())
        backup = backup_file(self.state(), TARGET)
        self.assertTrue(backup.exists(), "a successful dedupe installs the main backup")
        self.assertEqual(backup.read_text(encoding="utf-8").split(), ["A", "B", "A", "C", "B"])
        combined = result.stdout + result.stderr
        self.assertIn("in-place", combined)
        self.assertNotIn("trial-dedupe apply", combined)

    def test_dedupe_presence_succeeds_with_forward_winning_too(self) -> None:
        result = self.run_dedupe({"FAKE_WINNING_MAPPING": "forward"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.apply_mappings(), [])
        self.assertEqual(len(self.dedupe_in_place_calls()), 1)
        self.assertFalse(mapping_file(self.state(), TARGET).exists())

    def test_dedupe_ignores_recorded_mapping(self) -> None:
        mapfile = mapping_file(self.state(), TARGET)
        mapfile.parent.mkdir(parents=True, exist_ok=True)
        mapfile.write_text(
            "MAPPING: forward\nTHROWAWAY: %s\nTARGET: %s\n"
            "SORT: self-probe: target's own sort\nTIMESTAMP: %d\n"
            % (TARGET, TARGET, int(time.time())),
            encoding="utf-8",
        )
        result = self.run_dedupe({"FAKE_WINNING_MAPPING": "reversed"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.apply_mappings(), [])
        self.assertEqual(len(self.dedupe_in_place_calls()), 1)
        self.assertNotIn("trial-dedupe apply", result.stdout + result.stderr)
        # Presence dedupe neither reads nor rewrites the mapping.
        self.assertEqual(read_fields(mapfile)["MAPPING"], "forward")

    def test_clean_playlist_applies_nothing_and_needs_no_mapping(self) -> None:
        result = self.run_dedupe(
            {"FAKE_DUMP_IDS": "A B C", "FAKE_WINNING_MAPPING": "forward"}
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.apply_mappings(), [])
        self.assertFalse(mapping_file(self.state(), TARGET).exists())
        self.assertIn("nothing was applied", result.stdout + result.stderr)

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

    def test_menu_dedupe_uses_presence_path(self) -> None:
        env = dict(self.env)
        env["FAKE_WINNING_MAPPING"] = "reversed"
        result = subprocess.run(
            ["bash", str(ROOT / "run.sh"), "menu"],
            input="3\n%s\n0\n" % TARGET,
            capture_output=True,
            text=True,
            env=env,
            timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.apply_mappings(), [])
        self.assertEqual(len(self.dedupe_in_place_calls()), 1)
        self.assertNotIn("sort-probe.applescript", self.call_basenames())
        self.assertFalse(mapping_file(self.state(), TARGET).exists())


class DailyTrialDedupeTests(unittest.TestCase):
    """daily.sh with a stub run.sh: duplicate probe -> presence dedupe."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.install = self.base / "install"
        self.install.mkdir()
        self.state = self.base / "state"
        self.state.mkdir()
        self.backups = self.base / "backups"
        self.backups.mkdir()
        shutil.copy(ROOT / "daily.sh", self.install / "daily.sh")
        check = self.install / "check-python.sh"
        check.write_text('#!/bin/bash\necho "/usr/bin/python3 (Python 3.12.0)"\n', encoding="utf-8")
        check.chmod(0o755)
        stub = self.install / "run.sh"
        stub.write_text(
            "#!/bin/bash\n"
            "echo \"$*\" >> \"$STUB_CALLS\"\n"
            "if [ \"$1\" = \"selfprobe\" ]; then\n"
            "  if [ \"$2\" = \"$STUB_DUPLICATE_TARGET\" ]; then\n"
            "    echo \"sort-probe: playlist \\\"$2\\\" contains a duplicate song entry\" >&2\n"
            "    exit 1\n"
            "  fi\n"
            "  python3 - \"$2\" <<'PY'\n"
            "import hashlib, os, sys, time\n"
            "from pathlib import Path\n"
            "name = sys.argv[1]\n"
            "safe = name.replace(' ', '_').replace('/', '_')\n"
            "digest = hashlib.sha256(name.encode()).hexdigest()[:12]\n"
            "Path(os.environ['SETER_STATE_DIR']).joinpath(f'sort-mapping-{safe}-{digest}.txt').write_text(\n"
            "    f\"MAPPING: reversed\\nTHROWAWAY: {name}\\nTARGET: {name}\\n\"\n"
            "    f\"SORT: self-probe: target's own sort\\nTIMESTAMP: {int(time.time())}\\n\")\n"
            "PY\n"
            "  exit 0\n"
            "fi\n"
            "if [ \"$1\" = \"dedupe\" ]; then\n"
            "  if [ -n \"${STUB_DEDUPE_FAIL:-}\" ]; then\n"
            "    echo \"stub dedupe failed for $2\" >&2; exit 1\n"
            "  fi\n"
            "  python3 - \"$2\" <<'PY'\n"
            "import hashlib, os, sys, time\n"
            "from pathlib import Path\n"
            "name = sys.argv[1]\n"
            "safe = name.replace(' ', '_').replace('/', '_')\n"
            "digest = hashlib.sha256(name.encode()).hexdigest()[:12]\n"
            "Path(os.environ['SETER_STATE_DIR']).joinpath(f'sort-mapping-{safe}-{digest}.txt').write_text(\n"
            "    f\"MAPPING: reversed\\nTHROWAWAY: {name}\\nTARGET: {name}\\n\"\n"
            "    f\"SORT: trial-dedupe: verified by dedupe apply\\nTIMESTAMP: {int(time.time())}\\n\")\n"
            "PY\n"
            "  exit 0\n"
            "fi\n"
            "exit 0\n",
            encoding="utf-8",
        )
        stub.chmod(0o755)
        self.calls = self.base / "calls.log"
        self.env = dict(os.environ)
        self.env["SETER_STATE_DIR"] = str(self.state)
        self.env["SETER_BACKUP_DIR"] = str(self.backups)
        self.env["STUB_CALLS"] = str(self.calls)
        today = time.strftime("%Y-%m-%d")
        (self.backups / f"library-manifest-{today}.tsv").write_text(
            "persistent_id\tartist\talbum\ttitle\n", encoding="utf-8"
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_daily(self, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
        env = dict(self.env)
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            ["bash", str(self.install / "daily.sh"), TARGET],
            capture_output=True,
            text=True,
            env=env,
            timeout=60,
        )

    def test_daily_duplicate_probe_triggers_presence_dedupe_then_continues(self) -> None:
        result = self.run_daily({"STUB_DUPLICATE_TARGET": TARGET})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls.read_text(encoding="utf-8").splitlines()
        self.assertEqual(
            calls,
            [
                "selfprobe " + TARGET,
                "dedupe " + TARGET,
                "selfprobe SeTeR Rediscover",
                "selfprobe SeTeR Flow",
                "dedupe " + TARGET,
                "shuffle " + TARGET,
                "flow",
                "rediscover",
            ],
            "duplicate probe -> in-place dedupe -> Rediscover probe -> Flow probe -> normal steps",
        )
        self.assertIn("in-place dedupe cleaned", result.stdout + result.stderr)

    def test_daily_duplicate_probe_plus_failed_dedupe_stops_before_rediscover(self) -> None:
        result = self.run_daily(
            {"STUB_DUPLICATE_TARGET": TARGET, "STUB_DEDUPE_FAIL": "1"}
        )
        self.assertNotEqual(result.returncode, 0)
        calls = self.calls.read_text(encoding="utf-8").splitlines()
        self.assertEqual(calls, ["selfprobe " + TARGET, "dedupe " + TARGET])
        self.assertNotIn("shuffle", "\n".join(calls))


class TrialDedupeStructuralTests(unittest.TestCase):
    def test_trial_functions_exist_and_probe_refusal_unchanged(self) -> None:
        text = (ROOT / "run.sh").read_text(encoding="utf-8")
        self.assertIn("dedupe_trial_apply()", text)
        self.assertIn("record_trial_mapping()", text)
        self.assertIn("apply_order_mapped()", text)
        self.assertIn("neither forward nor reversed mapping verified", text)
        bridge = (ROOT / "bridge" / "sort-probe.applescript").read_text(encoding="utf-8")
        self.assertIn("contains a duplicate song entry", bridge)

    def test_daily_trial_fallback_only_on_duplicate_wording(self) -> None:
        text = (ROOT / "daily.sh").read_text(encoding="utf-8")
        self.assertIn('grep -q "duplicate song entry"', text)
        self.assertIn("trial-dedupe", text)

    def test_no_new_array_expansion(self) -> None:
        for name in ("run.sh", "daily.sh"):
            text = (ROOT / name).read_text(encoding="utf-8")
            code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
            for match in re.finditer(r"\$\{(\w+)\[@\]\}", code):
                self.assertEqual(
                    match.group(1),
                    "apply_args",
                    f"{name}: unexpected [@] expansion {match.group(0)}",
                )


if __name__ == "__main__":
    unittest.main()
