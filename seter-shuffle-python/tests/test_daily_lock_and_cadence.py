"""daily.sh: single-run lock and the optional probe cadence (stub run.sh)."""

from __future__ import annotations

import hashlib
import os
import sys
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tests"))

import test_selfprobe as _selfprobe  # module import: keeps the parent class out of this module's discovery

_Base = _selfprobe.DailyAutoProbeTests

TARGETS = ("My New Sandwich Recipe", "SeTeR Rediscover", "SeTeR Flow")


class DailyLockAndCadenceTests(_Base):
    def setUp(self) -> None:
        super().setUp()
        stub = self.install / "run.sh"
        text = stub.read_text(encoding="utf-8")
        stub.write_text(
            text.replace('echo "$*" >> "$STUB_CALLS"\n', 'echo "$*" >> "$STUB_CALLS"\necho "LOCKHELD=${SETER_LOCK_HELD:-}" >> "$STUB_CALLS.env"\n', 1),
            encoding="utf-8",
        )

    def write_mapping(self, target: str, age_hours: float) -> None:
        safe = target.replace(" ", "_").replace("/", "_")
        digest = hashlib.sha256(target.encode()).hexdigest()[:12]
        ts = int(time.time() - age_hours * 3600)
        (self.state / f"sort-mapping-{safe}-{digest}.txt").write_text(
            f"MAPPING: reversed\nTHROWAWAY: {target}\nTARGET: {target}\n"
            f"SORT: self-probe: target's own sort\nTIMESTAMP: {ts}\n",
            encoding="utf-8",
        )

    def probe_calls(self) -> list[str]:
        if not self.calls.exists():
            return []
        return [l for l in self.calls.read_text().splitlines() if l.startswith("selfprobe")]

    # ---- probe cadence ------------------------------------------------
    def test_default_still_probes_every_target_even_with_fresh_mappings(self) -> None:
        for t in TARGETS:
            self.write_mapping(t, 1)
        r = self.run_daily()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(len(self.probe_calls()), 3)

    def test_cadence_skips_probe_for_young_mappings(self) -> None:
        for t in TARGETS:
            self.write_mapping(t, 1)
        r = self.run_daily({"SETER_PROBE_MAX_AGE_HOURS": "12"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.probe_calls(), [])
        self.assertIn("daily self-probe skipped", r.stdout + r.stderr)
        calls = self.calls.read_text().splitlines()
        self.assertEqual(calls[-4:], [f"dedupe {TARGETS[0]}", f"shuffle {TARGETS[0]}", "flow", "rediscover"])

    def test_cadence_probes_only_the_old_one(self) -> None:
        self.write_mapping(TARGETS[0], 1)
        self.write_mapping(TARGETS[1], 20)  # older than the 12h cap, still under 48h
        self.write_mapping(TARGETS[2], 1)
        r = self.run_daily({"SETER_PROBE_MAX_AGE_HOURS": "12"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.probe_calls(), [f"selfprobe {TARGETS[1]}"])

    def test_cadence_without_a_mapping_probes(self) -> None:
        r = self.run_daily({"SETER_PROBE_MAX_AGE_HOURS": "12"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(len(self.probe_calls()), 3)

    def test_junk_cadence_value_means_off(self) -> None:
        for t in TARGETS:
            self.write_mapping(t, 1)
        r = self.run_daily({"SETER_PROBE_MAX_AGE_HOURS": "soon"})
        self.assertEqual(len(self.probe_calls()), 3)

    # ---- lock ---------------------------------------------------------
    def test_daily_refuses_when_another_run_holds_the_lock(self) -> None:
        lock = self.state / "run.lock.d"
        lock.mkdir()
        (lock / "pid").write_text(str(os.getpid()))  # this test process: alive
        (lock / "started").write_text(str(int(time.time())))
        r = self.run_daily()
        self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
        self.assertIn("DAILY SKIPPED", r.stdout + r.stderr)
        self.assertFalse(self.calls.exists(), "a refused daily run must not call run.sh at all")
        self.assertTrue(lock.exists(), "the other run's lock must be left alone")

    def test_daily_releases_lock_and_children_inherit_the_flag(self) -> None:
        r = self.run_daily()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse((self.state / "run.lock.d").exists(), "lock must be released on exit")
        flags = (Path(str(self.calls) + ".env")).read_text().splitlines()
        self.assertTrue(flags and all(f == "LOCKHELD=1" for f in flags), flags)

    def test_daily_releases_lock_after_a_failed_run(self) -> None:
        r = self.run_daily({"STUB_PROBE_FAIL": TARGETS[0]})
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse((self.state / "run.lock.d").exists())

    def test_dry_run_ignores_the_lock(self) -> None:
        for t in TARGETS:
            self.write_mapping(t, 1)
        lock = self.state / "run.lock.d"
        lock.mkdir()
        (lock / "pid").write_text(str(os.getpid()))
        (lock / "started").write_text(str(int(time.time())))
        r = self.run_daily({"SETER_DAILY_DRY_RUN": "1"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue(lock.exists())


# Don't re-run the parent's tests under this subclass.
for _name in dir(_Base):
    if _name.startswith("test_") and _name not in DailyLockAndCadenceTests.__dict__:
        setattr(DailyLockAndCadenceTests, _name, None)

del _Base  # the loader would otherwise collect the parent class from this module too

if __name__ == "__main__":
    unittest.main()
