"""Tests for the v3.0.10 stable daily dedupe fallback.

On 2026-10-31 the v3.0.9 daily run cleaned the main playlist
via its duplicate-only fallback, then exited at the SeTeR
Rediscover probe's duplicate refusal before shuffle, flow, or
rediscover ever ran: only the main playlist had a fallback.
This build gives all three daily targets the same fallback,
through one helper, probe_target in daily.sh:

  * a probe that refuses ONLY on duplicate entries triggers
    one in-place dedupe for that target, then one re-probe
    of the clean target for a fresh mapping;
  * a probe failure for any other reason, a failed dedupe,
    or a re-probe that still refuses (or fails) stops the
    whole daily run before the next target is probed and
    before any build, with no second dedupe attempt;
  * the dedupe stub here writes NO mapping, mirroring the
    real in-place dedupe, so a successful daily run after a
    fallback proves the re-probe supplied the mapping the
    mapping check then passes on, not the dedupe.

No Mac is involved: a stub run.sh stands in for daily.sh's
calls, and today's manifest already exists so daily.sh never
touches osascript.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAIN = "My New Sandwich Recipe"
REDISCOVER = "SeTeR Rediscover"
FLOW = "SeTeR Flow"


class DailyDedupeFallbackTests(unittest.TestCase):
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
            "  safe=\"$(printf '%s' \"$2\" | tr ' /' '__')\"\n"
            "  count_file=\"$SETER_STATE_DIR/probe-count-$safe\"\n"
            "  if [ -n \"${STUB_PROBE_FAIL:-}\" ] && [ \"$2\" = \"$STUB_PROBE_FAIL\" ]; then\n"
            "    echo \"stub selfprobe failed for $2\" >&2; exit 1\n"
            "  fi\n"
            "  if [ -n \"${STUB_DUPLICATE_TARGET:-}\" ] && [ \"$2\" = \"$STUB_DUPLICATE_TARGET\" ] && [ ! -f \"$count_file\" ]; then\n"
            "    touch \"$count_file\"\n"
            "    echo \"sort-probe: playlist \\\"$2\\\" contains a duplicate song entry\" >&2\n"
            "    exit 1\n"
            "  fi\n"
            "  if [ -n \"${STUB_REPROBE_FAIL:-}\" ] && [ \"$2\" = \"$STUB_REPROBE_FAIL\" ] && [ -f \"$count_file\" ]; then\n"
            "    echo \"stub re-probe failed for $2\" >&2; exit 1\n"
            "  fi\n"
            "  if [ -n \"${STUB_REPROBE_DUPLICATE:-}\" ] && [ \"$2\" = \"$STUB_REPROBE_DUPLICATE\" ] && [ -f \"$count_file\" ]; then\n"
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
            ["bash", str(self.install / "daily.sh"), MAIN],
            capture_output=True,
            text=True,
            env=env,
            timeout=60,
        )

    def call_lines(self) -> list[str]:
        return self.calls.read_text(encoding="utf-8").splitlines()

    def test_rediscover_duplicate_probe_dedupes_reprobes_and_completes(self) -> None:
        result = self.run_daily({"STUB_DUPLICATE_TARGET": REDISCOVER})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            self.call_lines(),
            [
                f"selfprobe {MAIN}",
                f"selfprobe {REDISCOVER}",
                f"dedupe {REDISCOVER}",
                f"selfprobe {REDISCOVER}",
                f"selfprobe {FLOW}",
                f"dedupe {MAIN}",
                f"shuffle {MAIN}",
                "flow",
                "rediscover",
            ],
            "the 2026-10-31 stall, replayed: Rediscover dedupes, re-probes, and the daily run finishes",
        )
        combined = result.stdout + result.stderr
        self.assertIn(f"in-place dedupe cleaned '{REDISCOVER}'", combined)
        self.assertIn("re-probing the clean playlist", combined)

    def test_flow_duplicate_probe_dedupes_reprobes_and_completes(self) -> None:
        result = self.run_daily({"STUB_DUPLICATE_TARGET": FLOW})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            self.call_lines(),
            [
                f"selfprobe {MAIN}",
                f"selfprobe {REDISCOVER}",
                f"selfprobe {FLOW}",
                f"dedupe {FLOW}",
                f"selfprobe {FLOW}",
                f"dedupe {MAIN}",
                f"shuffle {MAIN}",
                "flow",
                "rediscover",
            ],
        )

    def test_main_duplicate_probe_now_reprobes_after_dedupe(self) -> None:
        result = self.run_daily({"STUB_DUPLICATE_TARGET": MAIN})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            self.call_lines(),
            [
                f"selfprobe {MAIN}",
                f"dedupe {MAIN}",
                f"selfprobe {MAIN}",
                f"selfprobe {REDISCOVER}",
                f"selfprobe {FLOW}",
                f"dedupe {MAIN}",
                f"shuffle {MAIN}",
                "flow",
                "rediscover",
            ],
            "the fallback is one helper for all targets: main now re-probes too, instead of relying on a mapping that survived the refused probe",
        )

    def test_rediscover_duplicate_plus_failed_dedupe_stops_before_flow_probe(self) -> None:
        result = self.run_daily(
            {"STUB_DUPLICATE_TARGET": REDISCOVER, "STUB_DEDUPE_FAIL": "1"}
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            self.call_lines(),
            [f"selfprobe {MAIN}", f"selfprobe {REDISCOVER}", f"dedupe {REDISCOVER}"],
        )
        self.assertNotIn("shuffle", "\n".join(self.call_lines()))

    def test_reprobe_failure_after_dedupe_stops_with_single_dedupe(self) -> None:
        result = self.run_daily(
            {"STUB_DUPLICATE_TARGET": REDISCOVER, "STUB_REPROBE_FAIL": REDISCOVER}
        )
        self.assertNotEqual(result.returncode, 0)
        calls = self.call_lines()
        self.assertEqual(
            calls,
            [
                f"selfprobe {MAIN}",
                f"selfprobe {REDISCOVER}",
                f"dedupe {REDISCOVER}",
                f"selfprobe {REDISCOVER}",
            ],
        )
        self.assertEqual(calls.count(f"dedupe {REDISCOVER}"), 1)
        self.assertNotIn(f"selfprobe {FLOW}", calls)

    def test_reprobe_still_duplicate_stops_with_single_dedupe(self) -> None:
        result = self.run_daily(
            {"STUB_DUPLICATE_TARGET": REDISCOVER, "STUB_REPROBE_DUPLICATE": REDISCOVER}
        )
        self.assertNotEqual(result.returncode, 0)
        calls = self.call_lines()
        self.assertEqual(calls.count(f"dedupe {REDISCOVER}"), 1)
        self.assertIn("no second dedupe attempt", result.stdout + result.stderr)
        self.assertNotIn(f"selfprobe {FLOW}", calls)


class DailyDedupeFallbackStructuralTests(unittest.TestCase):
    def test_probe_target_is_the_only_probe_path(self) -> None:
        text = (ROOT / "daily.sh").read_text(encoding="utf-8")
        self.assertIn("probe_target()", text)
        self.assertNotIn("probe_status", text)
        # Exactly two direct probe calls, both inside probe_target;
        # the probe block itself calls only probe_target.
        self.assertEqual(text.count('auto_self_probe "$target"'), 2)
        self.assertIn('probe_target "$PLAYLIST"', text)
        self.assertIn('probe_target "$REDISCOVER_PLAYLIST"', text)
        self.assertIn('probe_target "$FLOW_PLAYLIST"', text)
        # Exactly two dedupe invocations in daily.sh: the fallback
        # inside probe_target, and the normal step after the
        # mapping check.
        self.assertEqual(text.count('run.sh" dedupe'), 2)
        probe_pos = text.index('probe_target "$PLAYLIST"')
        check_pos = text.index('check_mapping "$PLAYLIST"')
        normal_dedupe_pos = text.index('run.sh" dedupe', check_pos)
        self.assertLess(probe_pos, check_pos)
        self.assertLess(check_pos, normal_dedupe_pos)


if __name__ == "__main__":
    unittest.main()
