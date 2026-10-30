"""Tests for v3.0.3 automatic self-probing of menu and direct builds.

v3.0.2 wired auto self-probe into daily.sh only. Spencer then
ran the menu on 3.0.2 and still got the gate failure, correctly,
because run.sh's menu code explicitly said it "never probes"
and called mapping_ready_for || continue. That is the gap this
release closes: probing must be automatic for menu and direct
builds too, not just the daily run.

What is tested here, without a Mac (AppleScript itself cannot
run here, so a fake `osascript` on PATH stands in for the
bridge, exactly as in test_selfprobe.py):
  * ensure_mapping_for with no mapping auto self-probes the
    target itself, records a fresh mapping, and returns 0.
  * ensure_mapping_for with a fresh mapping does NOT re-probe.
  * ensure_mapping_for with a stale (49h) mapping re-probes
    and refreshes the timestamp.
  * ensure_mapping_for with a failing probe (duplicate-entry
    refusal) returns non-zero, leaves no mapping, and makes
    no dump or apply call.
  * A direct ./run.sh shuffle with no mapping auto-probes
    first, then dumps, computes, and applies; with a fresh
    mapping it applies without probing; with a failing probe
    it aborts before any dump or apply.
  * The menu section contains ensure_mapping_for for every
    build target and no bare mapping_ready_for dispatch, and
    the pre-dump block ensures shuffle/dedupe/flow/rediscover
    (and undo/restore ensure before their mapping gate).
  * The duplicate refusal in bridge/sort-probe.applescript is
    unchanged, and no new bash 3.2 empty-array expansion was
    introduced.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN_TEXT = (ROOT / "run.sh").read_text()
SELF_PROBE_LABEL = "self-probe: target's own sort"

# Fake osascript: dispatch on the bridge script basename.
#   sort-probe.applescript: per FAKE_PROBE_MODE (ok-reversed,
#     ok-forward, duplicate, other); writes the snapshot, prints
#     the mapping line, and records the call.
#   dump-library.applescript: writes a 6-song library JSON to
#     the dump path argument and records the call.
#   apply-order.applescript: creates the per-run backup file
#     (argument 4) and records the call.
#   anything else (-e notifications, undo, etc.): succeed.
FAKE_OSASCRIPT = """#!/bin/bash
if [ "$1" = "-e" ]; then exit 0; fi
script="$1"
base="$(basename "$script")"
echo "$base $*" >> "$FAKE_CALLS"
case "$base" in
  sort-probe.applescript)
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
      duplicate)
        echo "sort-probe: playlist contains a duplicate song entry" >&2
        exit 1
        ;;
      other)
        printf 'ID1\\nID2\\nID3\\nID4\\nID5\\nID6\\n' > "$snapshot"
        echo "sort-probe: MAPPING: other" >&2
        exit 1
        ;;
    esac
    ;;
  dump-library.applescript)
    python3 - "$2" <<'PY'
import json, sys
tracks = []
for i in range(1, 7):
    tracks.append({"persistent_id": f"ID{i}", "artist": "Artist", "album": "Album",
                   "name": f"Song {i}", "genre": "Hip-Hop/Rap", "play_count": 3,
                   "rating": 0, "favorited": False, "disliked": False,
                   "skip_count": 0, "year": 2020})
json.dump({"tracks": tracks}, open(sys.argv[1], "w"))
PY
    exit 0
    ;;
  apply-order.applescript)
    touch "$4"
    exit 0
    ;;
  *)
    exit 0
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


def _function_lines(text, name):
    lines = text.splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith(name + "() {"))
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "}")
    return lines[start : end + 1]


class AutoProbeHarness(unittest.TestCase):
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
        self.calls.write_text("", encoding="utf-8")
        self.env = dict(os.environ)
        self.env["HOME"] = str(self.home)
        self.env["PATH"] = str(self.bindir) + os.pathsep + os.environ["PATH"]
        self.env["FAKE_CALLS"] = str(self.calls)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def state(self) -> Path:
        return self.home / "Library" / "Logs" / "seter-shuffle-python"

    def run_sh(self, args, mode="ok-reversed"):
        env = dict(self.env)
        env["FAKE_PROBE_MODE"] = mode
        return subprocess.run(
            ["bash", str(ROOT / "run.sh"), *args],
            capture_output=True, text=True, env=env, timeout=120,
        )

    def call_basenames(self):
        return [line.split()[0] for line in self.calls.read_text().splitlines() if line.strip()]

    def write_mapping(self, target, mapping="forward", age_s=0):
        mapfile = mapping_file(self.state(), target)
        mapfile.parent.mkdir(parents=True, exist_ok=True)
        mapfile.write_text(
            f"MAPPING: {mapping}\nTHROWAWAY: {target}\nTARGET: {target}\n"
            f"SORT: {SELF_PROBE_LABEL}\nTIMESTAMP: {int(time.time()) - age_s}\n",
            encoding="utf-8",
        )
        return mapfile


class EnsureMappingTests(AutoProbeHarness):
    def run_ensure(self, target, mode="ok-reversed"):
        # Extract ensure_mapping_for plus its helpers and run it
        # standalone against the temp HOME state dir.
        helpers = []
        for name in ("log", "logerr", "logfile", "mapping_file_for",
                     "mapping_status_for", "mapping_is_ready", "ensure_mapping_for"):
            if name in ("log", "logerr", "logfile"):
                helpers.append(next(l for l in RUN_TEXT.splitlines() if l.startswith(name + "() {")))
            else:
                helpers.append("\n".join(_function_lines(RUN_TEXT, name)))
        state = self.state()
        state.mkdir(parents=True, exist_ok=True)
        script = (
            f"ROOT={ROOT}\nSTATE={state}\nLOG={state}/run.log\n"
            + "\n".join(helpers)
            + f"\nif ensure_mapping_for '{target}'; then echo ENSURED; else echo REFUSED; fi\n"
        )
        env = dict(self.env)
        env["FAKE_PROBE_MODE"] = mode
        return subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env, timeout=60)

    def test_no_mapping_auto_probes_and_succeeds(self):
        proc = self.run_ensure("My New Sandwich Recipe")
        self.assertIn("ENSURED", proc.stdout, proc.stdout + proc.stderr)
        fields = read_mapping(mapping_file(self.state(), "My New Sandwich Recipe"))
        self.assertEqual(fields["MAPPING"], "reversed")
        self.assertEqual(fields["SORT"], SELF_PROBE_LABEL)
        self.assertIn("sort-probe.applescript", self.call_basenames())

    def test_fresh_mapping_does_not_reprobe(self):
        self.write_mapping("My New Sandwich Recipe")
        proc = self.run_ensure("My New Sandwich Recipe")
        self.assertIn("ENSURED", proc.stdout, proc.stdout + proc.stderr)
        self.assertNotIn("sort-probe.applescript", self.call_basenames(),
                         "a fresh mapping must be reused with no extra rebuild")

    def test_stale_mapping_reprobes_and_refreshes(self):
        mapfile = self.write_mapping("My New Sandwich Recipe", age_s=49 * 3600)
        old_ts = read_mapping(mapfile)["TIMESTAMP"]
        proc = self.run_ensure("My New Sandwich Recipe")
        self.assertIn("ENSURED", proc.stdout, proc.stdout + proc.stderr)
        self.assertIn("sort-probe.applescript", self.call_basenames())
        self.assertGreater(int(read_mapping(mapfile)["TIMESTAMP"]), int(old_ts))

    def test_probe_failure_refuses_with_no_mapping(self):
        proc = self.run_ensure("My New Sandwich Recipe", mode="duplicate")
        self.assertIn("REFUSED", proc.stdout, proc.stdout + proc.stderr)
        self.assertIn("selfprobe", proc.stdout + proc.stderr)
        self.assertFalse(mapping_file(self.state(), "My New Sandwich Recipe").exists(),
                         "a duplicate refusal changes nothing and records no mapping")


class DirectBuildAutoProbeTests(AutoProbeHarness):
    def test_direct_shuffle_no_mapping_probes_then_applies(self):
        result = self.run_sh(["shuffle", "My New Sandwich Recipe"])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        names = self.call_basenames()
        self.assertIn("sort-probe.applescript", names)
        self.assertIn("dump-library.applescript", names)
        self.assertIn("apply-order.applescript", names)
        self.assertLess(names.index("sort-probe.applescript"), names.index("dump-library.applescript"),
                        "the probe must run before any dump")
        self.assertLess(names.index("dump-library.applescript"), names.index("apply-order.applescript"))

    def test_direct_shuffle_fresh_mapping_skips_probe(self):
        self.write_mapping("My New Sandwich Recipe")
        result = self.run_sh(["shuffle", "My New Sandwich Recipe"])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        names = self.call_basenames()
        self.assertNotIn("sort-probe.applescript", names)
        self.assertIn("apply-order.applescript", names)

    def test_direct_shuffle_stale_mapping_reprobes(self):
        self.write_mapping("My New Sandwich Recipe", age_s=49 * 3600)
        result = self.run_sh(["shuffle", "My New Sandwich Recipe"])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("sort-probe.applescript", self.call_basenames())
        self.assertIn("apply-order.applescript", self.call_basenames())

    def test_direct_shuffle_probe_failure_aborts_before_dump_and_apply(self):
        result = self.run_sh(["shuffle", "My New Sandwich Recipe"], mode="duplicate")
        self.assertNotEqual(result.returncode, 0)
        names = self.call_basenames()
        self.assertIn("sort-probe.applescript", names)
        self.assertNotIn("dump-library.applescript", names, "a failed probe must abort before any dump")
        self.assertNotIn("apply-order.applescript", names)
        self.assertFalse(mapping_file(self.state(), "My New Sandwich Recipe").exists())
        combined = result.stdout + result.stderr
        self.assertIn("selfprobe", combined)
        self.assertIn("GATE FAILED", combined)

    def test_direct_shuffle_probe_other_aborts_before_dump(self):
        result = self.run_sh(["shuffle", "My New Sandwich Recipe"], mode="other")
        self.assertNotEqual(result.returncode, 0)
        names = self.call_basenames()
        self.assertNotIn("dump-library.applescript", names)
        self.assertNotIn("apply-order.applescript", names)


class AutoProbeStructuralTests(unittest.TestCase):
    def test_menu_uses_ensure_not_bare_ready(self):
        menu = RUN_TEXT.split('if [ "$CMD" = "menu" ]')[1].split("# Sort-probe command")[0]
        for target in ('"$menu_target"', '"SeTeR Rediscover"', '"SeTeR Flow"', '"$pl"'):
            self.assertIn(f"ensure_mapping_for {target}", menu)
        self.assertNotIn("mapping_ready_for ", menu)
        self.assertNotIn("never probes", menu)

    def test_pre_dump_ensures_every_build_target(self):
        block = RUN_TEXT.split("# Automatic self-probe before any dump")[1].split("# Dump:")[0]
        self.assertIn('ensure_mapping_for "${SHUFFLE_PLAYLIST:-SeTeR Shuffle}"', block)
        self.assertIn('ensure_mapping_for "$2"', block)
        self.assertIn('ensure_mapping_for "SeTeR Flow"', block)
        self.assertIn('ensure_mapping_for "SeTeR Rediscover"', block)

    def test_undo_restore_ensure_before_mapping_gate(self):
        for mode in ("undo", "restore"):
            section = RUN_TEXT.split(f'if [ "$CMD" = "{mode}" ]')[1]
            self.assertLess(
                section.index('ensure_mapping_for "$PLAYLIST"'),
                section.index('mapping_for_build "$PLAYLIST"'),
            )

    def test_gate_messages_name_selfprobe_not_manual_sortprobe_first(self):
        body = "\n".join(_function_lines(RUN_TEXT, "mapping_for_build"))
        self.assertIn("selfprobe", body)
        self.assertNotIn("run ./run.sh sortprobe", body)

    def test_no_new_array_expansion(self):
        for name in ("run.sh", "daily.sh"):
            text = (ROOT / name).read_text(encoding="utf-8")
            code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
            for match in re.finditer(r"\$\{(\w+)\[@\]\}", code):
                self.assertEqual(match.group(1), "apply_args",
                                 f"{name}: unexpected [@] expansion {match.group(0)}")

    def test_duplicate_refusal_unchanged_in_bridge(self):
        text = (ROOT / "bridge" / "sort-probe.applescript").read_text(encoding="utf-8")
        self.assertIn("contains a duplicate song entry", text)


if __name__ == "__main__":
    unittest.main()
