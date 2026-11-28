"""The single-run lock in run.sh (bash, no Music needed).

The lock block is cut out of the real script between its marker comment
and the end of acquire_lock, so these tests exercise the shipped code,
not a copy. daily.sh used to ship its own copy; since
exp-2026-11-26.1 it is only a shortcut for `run.sh daily`, and the
daily run takes run.sh's lock itself (so a dry run can skip it and
a refusal can say DAILY SKIPPED).
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def lock_block(script: str) -> str:
    text = (ROOT / script).read_text(encoding="utf-8")
    start = text.index("# ---- single-run lock")
    end = text.index("\n}\n", text.index("acquire_lock() {")) + 3
    return text[start:end]


class LockTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state = Path(self.tmp.name)

    def bash(self, script_name: str, body: str, env_extra: str = "") -> subprocess.CompletedProcess:
        prog = (
            f'set -uo pipefail\nSTATE="{self.state}"\nLOG="{self.state}/log"\n{env_extra}\n'
            + lock_block(script_name) + "\n" + body
        )
        return subprocess.run(["bash", "-c", prog], capture_output=True, text=True, timeout=30)

    def test_run_sh_ships_the_lock_block_and_daily_sh_delegates_to_it(self):
        block = lock_block("run.sh")
        self.assertIn("acquire_lock() {", block)
        self.assertIn("release_lock() {", block)
        daily = (ROOT / "daily.sh").read_text(encoding="utf-8")
        self.assertIn('exec "$ROOT/run.sh" daily "$@"', daily)
        self.assertNotIn("acquire_lock", daily)
        self.assertNotIn("# ---- single-run lock", daily)

    def test_acquire_release_and_reacquire(self):
        r = self.bash("run.sh", 'acquire_lock one && test -d "$SETER_LOCK_DIR" && release_lock && ! test -d "$SETER_LOCK_DIR" && acquire_lock two && echo OK')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("OK", r.stdout)

    def test_second_run_is_refused_while_owner_alive(self):
        holder = subprocess.Popen(
            ["bash", "-c", f'set -u; STATE="{self.state}"; LOG="{self.state}/log"; {lock_block("run.sh")}\nacquire_lock holder && echo held && sleep 30'],
            stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(holder.stdout.readline().strip(), "held")
            r = self.bash("run.sh", 'if acquire_lock second; then echo GOT; else echo "REFUSED: $LOCK_HOLDER"; fi')
            self.assertIn("REFUSED", r.stdout)
            self.assertNotIn("GOT", r.stdout)
            self.assertIn(f"pid {holder.pid}", r.stdout)
        finally:
            holder.kill(); holder.wait()

    def test_stale_lock_from_dead_pid_is_taken_over(self):
        d = self.state / "run.lock.d"
        d.mkdir()
        dead = subprocess.Popen(["true"]); dead.wait()
        (d / "pid").write_text(str(dead.pid))
        (d / "started").write_text(str(int(time.time())))
        r = self.bash("run.sh", 'acquire_lock x && echo TOOK')
        self.assertIn("TOOK", r.stdout, r.stderr)
        self.assertIn("stale run lock removed", (self.state / "log").read_text())

    def test_old_lock_is_stale_even_if_pid_is_alive(self):
        d = self.state / "run.lock.d"
        d.mkdir()
        (d / "pid").write_text("1")  # init: always alive
        (d / "started").write_text(str(int(time.time()) - 13 * 3600))
        r = self.bash("run.sh", 'acquire_lock x && echo TOOK')
        self.assertIn("TOOK", r.stdout, r.stderr)

    def test_inherited_lock_flag_skips_locking(self):
        d = self.state / "run.lock.d"
        d.mkdir()
        (d / "pid").write_text("1"); (d / "started").write_text(str(int(time.time())))
        r = self.bash("run.sh", 'acquire_lock child && echo SKIPPED_LOCK', env_extra="export SETER_LOCK_HELD=1")
        self.assertIn("SKIPPED_LOCK", r.stdout)

    def test_only_the_owner_releases(self):
        d = self.state / "run.lock.d"
        d.mkdir()
        (d / "pid").write_text("999999")
        r = self.bash("run.sh", 'LOCK_OWNED=1; release_lock; test -d "$SETER_LOCK_DIR" && echo STILL_THERE')
        self.assertIn("STILL_THERE", r.stdout)


class WiringTests(unittest.TestCase):
    """The lock must actually be wired in (cheap text checks on the scripts)."""

    def test_run_sh_locks_mutating_commands_only(self):
        text = (ROOT / "run.sh").read_text(encoding="utf-8")
        self.assertIn("audit|flowPreview|rediscover-preview|menu|daily-status|organize|backups|daily) ;;", text)
        self.assertIn('acquire_lock "run.sh $CMD"', text)
        self.assertIn("trap 'rm -rf \"$WORK\"; release_lock' EXIT", text)

    def test_daily_locks_unless_dry_run_and_probe_cadence_defaults_off(self):
        text = (ROOT / "run.sh").read_text(encoding="utf-8")
        start = text.index("# ---- daily mode (exp-2026-11-26.1)")
        end = text.index("# ---- end daily mode ----")
        daily = text[start:end]
        self.assertIn('acquire_lock "run.sh daily"', daily)
        self.assertIn('if [ -z "${SETER_DAILY_DRY_RUN:-}" ]; then\n    if ! acquire_lock "run.sh daily"; then', daily)
        self.assertIn('PROBE_MAX_AGE_HOURS="${SETER_PROBE_MAX_AGE_HOURS:-0}"', daily)
        self.assertNotIn("trap 'rm -rf \"$WORK\"' EXIT", daily)  # would drop the lock release


if __name__ == "__main__":
    unittest.main()
