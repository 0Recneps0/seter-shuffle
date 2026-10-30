"""Tests for v3.0.2 automatic self-probing.

Spencer's 2026-10-29 correction, which supersedes the
throwaway-only rule for sortprobe: Apple Music remembers each
playlist's own sort, so probing the actual target playlist
itself, under its own sort, eliminates the mapping-transfer
error by construction. The earlier ban on using the target as
the throwaway was over-cautious for sortprobe specifically
(it still holds for test shuffles: never shuffle a real
playlist as a test).

What is tested here, without a Mac (AppleScript itself cannot
run here, so a fake `osascript` on PATH stands in for the
bridge, and a stub `run.sh` stands in for daily.sh's calls):
  * ./run.sh selfprobe <target> records THROWAWAY == target
    and SORT == the self-probe label, accepted by the mapping
    gate (mapping_for_build only requires a non-empty label).
  * ./run.sh sortprobe with throwaway == target is the same
    self-probe: the user-supplied sort label is replaced by
    the self-probe label.
  * A self-probe whose restore could not be verified still
    records its measured mapping (so ./run.sh restore can run)
    but exits non-zero and names the snapshot.
  * A self-probe returning "other" deletes the mapping and
    exits non-zero; a duplicate-entry refusal changes nothing.
  * daily.sh auto self-probes each target BEFORE the mapping
    check and before any build, in playlist-then-Rediscover
    order; a first-target probe failure stops the run before
    the second probe and before any build.
  * The duplicate refusal in bridge/sort-probe.applescript is
    unchanged, and no new bash 3.2 empty-array expansion was
    introduced by the self-probe code.
"""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SELF_PROBE_LABEL = "self-probe: target's own sort"

FAKE_OSASCRIPT = """#!/bin/bash
# Fake osascript for run.sh selfprobe/sortprobe tests.
# notify calls pass -e: succeed silently. The sort-probe call
# passes <script> <playlist> <snapshot>: behave per FAKE_PROBE_MODE.
if [ "$1" = "-e" ]; then exit 0; fi
playlist="${@: -2:1}"
snapshot="${@: -1}"
mode="${FAKE_PROBE_MODE:-ok-reversed}"
case "$mode" in
  ok-forward)
    printf 'ID1\\nID2\\nID3\\nID4\\nID5\\nID6\\n' > "$snapshot"
    printf 'MAPPING: forward\\nSORTPROBE_OK\\n'
    exit 0
    ;;
  ok-reversed)
    printf 'ID1\\nID2\\nID3\\nID4\\nID5\\nID6\\n' > "$snapshot"
    printf 'MAPPING: reversed\\nSORTPROBE_OK\\n'
    exit 0
    ;;
  other)
    printf 'ID1\\nID2\\nID3\\nID4\\nID5\\nID6\\n' > "$snapshot"
    echo "sort-probe: MAPPING: other (read-back matched neither build nor reverse)" >&2
    exit 1
    ;;
  restore-failed)
    printf 'ID1\\nID2\\nID3\\nID4\\nID5\\nID6\\n' > "$snapshot"
    echo "sort-probe: MAPPING: reversed but the throwaway restore to its snapshot could not be verified; snapshot at $snapshot" >&2
    exit 1
    ;;
  duplicate)
    echo "sort-probe: playlist \\"$playlist\\" contains a duplicate song entry" >&2
    exit 1
    ;;
  *)
    echo "unknown FAKE_PROBE_MODE: $mode" >&2
    exit 2
    ;;
esac
"""


def mapping_file(state: Path, name: str) -> Path:
    safe = name.replace("\n", "_").replace("\r", "_").replace(" ", "_").replace("/", "_")
    digest = hashlib.sha256(name.encode()).hexdigest()[:12]
    return state / f"sort-mapping-{safe}-{digest}.txt"


def read_mapping(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        key, _, value = line.partition(": ")
        out[key] = value
    return out


class FakeOsascriptHarness(unittest.TestCase):
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
        self.env = dict(os.environ)
        self.env["HOME"] = str(self.home)
        self.env["PATH"] = str(self.bindir) + os.pathsep + os.environ["PATH"]

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def state(self) -> Path:
        return self.home / "Library" / "Logs" / "seter-shuffle-python"

    def run_probe(self, args: list[str], mode: str) -> subprocess.CompletedProcess:
        env = dict(self.env)
        env["FAKE_PROBE_MODE"] = mode
        return subprocess.run(
            ["bash", str(ROOT / "run.sh"), *args],
            capture_output=True,
            text=True,
            env=env,
            timeout=60,
        )

    def test_selfprobe_records_target_and_label(self) -> None:
        result = self.run_probe(["selfprobe", "My New Sandwich Recipe"], "ok-reversed")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        mapfile = mapping_file(self.state(), "My New Sandwich Recipe")
        self.assertTrue(mapfile.exists())
        fields = read_mapping(mapfile)
        self.assertEqual(fields["MAPPING"], "reversed")
        self.assertEqual(fields["THROWAWAY"], "My New Sandwich Recipe")
        self.assertEqual(fields["TARGET"], "My New Sandwich Recipe")
        self.assertEqual(fields["SORT"], SELF_PROBE_LABEL)
        self.assertTrue(fields["TIMESTAMP"].isdigit())
        self.assertLess(int(time.time()) - int(fields["TIMESTAMP"]), 60)

    def test_sortprobe_with_throwaway_equal_to_target_is_selfprobe(self) -> None:
        # A user-supplied sort label must NOT survive a self-probe:
        # the recorded label is the self-probe label.
        result = self.run_probe(
            ["sortprobe", "My New Sandwich Recipe", "My New Sandwich Recipe", "Playlist Order descending"],
            "ok-forward",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        fields = read_mapping(mapping_file(self.state(), "My New Sandwich Recipe"))
        self.assertEqual(fields["MAPPING"], "forward")
        self.assertEqual(fields["THROWAWAY"], "My New Sandwich Recipe")
        self.assertEqual(fields["SORT"], SELF_PROBE_LABEL)

    def test_selfprobe_other_deletes_mapping(self) -> None:
        mapfile = mapping_file(self.state(), "My New Sandwich Recipe")
        mapfile.parent.mkdir(parents=True, exist_ok=True)
        mapfile.write_text(
            "MAPPING: forward\nTHROWAWAY: My New Sandwich Recipe\n"
            "TARGET: My New Sandwich Recipe\nSORT: %s\nTIMESTAMP: %d\n"
            % (SELF_PROBE_LABEL, int(time.time())),
            encoding="utf-8",
        )
        result = self.run_probe(["selfprobe", "My New Sandwich Recipe"], "other")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(mapfile.exists(), "an 'other' self-probe must delete the mapping")
        self.assertIn("sort-probe-snapshot.txt", result.stdout + result.stderr)

    def test_selfprobe_duplicate_refusal_changes_nothing(self) -> None:
        result = self.run_probe(["selfprobe", "My New Sandwich Recipe"], "duplicate")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(
            mapping_file(self.state(), "My New Sandwich Recipe").exists()
        )
        self.assertFalse(
            (self.state() / "sort-probe-snapshot.txt").exists(),
            "a duplicate refusal writes no snapshot and changes nothing",
        )

    def test_selfprobe_restore_failed_records_mapping_but_fails(self) -> None:
        result = self.run_probe(["selfprobe", "My New Sandwich Recipe"], "restore-failed")
        self.assertNotEqual(result.returncode, 0)
        # Exception to the delete-on-failure rule: the mapping was
        # measured, and deleting it would block ./run.sh restore,
        # the only recovery for a target left holding the rotation.
        mapfile = mapping_file(self.state(), "My New Sandwich Recipe")
        self.assertTrue(mapfile.exists())
        fields = read_mapping(mapfile)
        self.assertEqual(fields["MAPPING"], "reversed")
        combined = result.stdout + result.stderr
        self.assertIn("sort-probe-snapshot.txt", combined)
        self.assertIn("restore 'My New Sandwich Recipe'", combined)

    def test_selfprobe_needs_playlist(self) -> None:
        result = self.run_probe(["selfprobe"], "ok-reversed")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("selfprobe", result.stdout + result.stderr)


class DailyAutoProbeTests(unittest.TestCase):
    """daily.sh with a stub run.sh: prove probe-before-check-before-build."""

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
        # Stub check-python.sh: daily.sh calls it directly.
        check = self.install / "check-python.sh"
        check.write_text('#!/bin/bash\necho "/usr/bin/python3 (Python 3.12.0)"\n', encoding="utf-8")
        check.chmod(0o755)
        # Stub run.sh: records invocations, and for selfprobe writes
        # a fresh mapping file (or fails, per STUB_PROBE_FAIL).
        stub = self.install / "run.sh"
        stub.write_text(
            "#!/bin/bash\n"
            "echo \"$*\" >> \"$STUB_CALLS\"\n"
            "if [ \"$1\" = \"selfprobe\" ]; then\n"
            "  if [ -n \"${STUB_PROBE_FAIL:-}\" ] && [ \"$2\" = \"$STUB_PROBE_FAIL\" ]; then\n"
            "    echo \"stub selfprobe failed for $2\" >&2; exit 1\n"
            "  fi\n"
            "  python3 - \"$2\" <<'PY'\n"
            "import hashlib, os, sys, time\n"
            "from pathlib import Path\n"
            "name = sys.argv[1]\n"
            "safe = name.replace(' ', '_').replace('/', '_')\n"
            "digest = hashlib.sha256(name.encode()).hexdigest()[:12]\n"
            "state = Path(os.environ['SETER_STATE_DIR'])\n"
            "state.joinpath(f'sort-mapping-{safe}-{digest}.txt').write_text(\n"
            "    f\"MAPPING: reversed\\nTHROWAWAY: {name}\\nTARGET: {name}\\n\"\n"
            "    f\"SORT: self-probe: target's own sort\\nTIMESTAMP: {int(time.time())}\\n\")\n"
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
        # Today's manifest already exists, so daily.sh skips the
        # osascript library dump (no Music here).
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
            ["bash", str(self.install / "daily.sh"), "My New Sandwich Recipe"],
            capture_output=True,
            text=True,
            env=env,
            timeout=60,
        )

    def test_daily_auto_probes_both_targets_before_build(self) -> None:
        result = self.run_daily()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls.read_text(encoding="utf-8").splitlines()
        self.assertEqual(
            calls,
            [
                "selfprobe My New Sandwich Recipe",
                "selfprobe SeTeR Rediscover",
                "dedupe My New Sandwich Recipe",
                "shuffle My New Sandwich Recipe",
                "rediscover",
            ],
            "probe playlist, probe Rediscover, then mapping check, then builds",
        )
        combined = result.stdout + result.stderr
        self.assertIn("auto self-probe OK for 'My New Sandwich Recipe'", combined)
        self.assertIn("auto self-probe OK for 'SeTeR Rediscover'", combined)

    def test_daily_first_probe_failure_stops_before_second_probe_and_build(self) -> None:
        result = self.run_daily({"STUB_PROBE_FAIL": "My New Sandwich Recipe"})
        self.assertNotEqual(result.returncode, 0)
        calls = self.calls.read_text(encoding="utf-8").splitlines()
        self.assertEqual(
            calls, ["selfprobe My New Sandwich Recipe"],
            "a failed first probe must not trigger the second probe (shared snapshot file) or any build",
        )
        combined = result.stdout + result.stderr
        self.assertIn("auto self-probe failed for 'My New Sandwich Recipe'", combined)
        self.assertIn("sort-probe-snapshot.txt", combined)
        self.assertIn("restore 'My New Sandwich Recipe'", combined)
        self.assertNotIn("daily dedupe done", combined)

    def test_daily_second_probe_failure_stops_before_build(self) -> None:
        result = self.run_daily({"STUB_PROBE_FAIL": "SeTeR Rediscover"})
        self.assertNotEqual(result.returncode, 0)
        calls = self.calls.read_text(encoding="utf-8").splitlines()
        self.assertEqual(
            calls,
            ["selfprobe My New Sandwich Recipe", "selfprobe SeTeR Rediscover"],
        )
        self.assertNotIn("dedupe", "\n".join(calls))

    def test_daily_dry_run_logs_planned_probes_without_running_them(self) -> None:
        # Dry runs change nothing: probes are planned, not run, and
        # the mapping check runs on the recorded mappings.
        for target in ("My New Sandwich Recipe", "SeTeR Rediscover"):
            safe = target.replace(" ", "_")
            digest = hashlib.sha256(target.encode()).hexdigest()[:12]
            (self.state / f"sort-mapping-{safe}-{digest}.txt").write_text(
                f"MAPPING: forward\nTHROWAWAY: {target}\nTARGET: {target}\n"
                f"SORT: self-probe: target's own sort\nTIMESTAMP: {int(time.time())}\n",
                encoding="utf-8",
            )
        result = self.run_daily({"SETER_DAILY_DRY_RUN": "1"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.calls.exists(), "dry run must not call run.sh at all")
        self.assertIn("auto self-probes skipped", result.stdout + result.stderr)


class SelfProbeStructuralTests(unittest.TestCase):
    def test_daily_probes_before_mapping_check_in_source(self) -> None:
        text = (ROOT / "daily.sh").read_text(encoding="utf-8")
        probe_pos = text.index("auto_self_probe \"$PLAYLIST\"")
        check_pos = text.index('check_mapping "$PLAYLIST"')
        dedupe_pos = text.index('run.sh" dedupe')
        self.assertLess(probe_pos, check_pos)
        self.assertLess(check_pos, dedupe_pos)
        # daily.sh invokes only selfprobe, never a throwaway sortprobe.
        self.assertIn('selfprobe "$target"', text)
        self.assertNotIn('run.sh" sortprobe', text)

    def test_no_new_array_expansion_in_selfprobe_code(self) -> None:
        for name in ("run.sh", "daily.sh"):
            text = (ROOT / name).read_text(encoding="utf-8")
            code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
            for match in re.finditer(r"\$\{(\w+)\[@\]\}", code):
                self.assertEqual(
                    match.group(1),
                    "apply_args",
                    f"{name}: unexpected [@] expansion {match.group(0)}",
                )

    def test_duplicate_refusal_unchanged_in_bridge(self) -> None:
        text = (ROOT / "bridge" / "sort-probe.applescript").read_text(encoding="utf-8")
        self.assertIn("contains a duplicate song entry", text)
        self.assertIn("at least 5 songs", text)

    def test_selfprobe_label_constant_in_run_sh(self) -> None:
        text = (ROOT / "run.sh").read_text(encoding="utf-8")
        self.assertIn('SELF_PROBE_LABEL="self-probe: target\'s own sort"', text)
        self.assertIn('"$CMD" = "selfprobe"', text)


if __name__ == "__main__":
    unittest.main()
