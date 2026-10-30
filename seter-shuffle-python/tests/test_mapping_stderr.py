"""Tests for the .3 mapping-gate error visibility fix.

Background: in .2, mapping_for_build() failures (no mapping file, bad
mapping word, bad timestamp, stale mapping) logged only via logfile(),
which writes to the run log and NOT to the terminal. A user running
./run.sh shuffle therefore saw the run stop after "compute shuffle
order" with no visible error. The .1 bug was the mirror image:
logging with log() tees to stdout, and mapping_for_build's output is
captured via $(...), so a log line polluted the captured mapping.

The .3 rule: failures in any function called inside $(...) go
through logerr() (log file AND stderr, never stdout). These tests
prove, by executing the real mapping_for_build() extracted from
run.sh under bash:
  - every failure case exits non-zero, prints GATE FAILED to stderr,
    and prints NOTHING to stdout;
  - a valid mapping still captures to exactly the mapping word, with
    nothing on stderr;
and structurally:
  - mapping_for_build() and probe_mode() contain no log() call;
  - their failure branches use logerr(), and logerr() routes to
    stderr (>&2) while appending to the log file.
"""

from __future__ import annotations

import subprocess
import tempfile
import textwrap
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN_SH = ROOT / "run.sh"


def _function_lines(text: str, name: str) -> list[str]:
    """Return the lines of a shell function definition by name."""
    lines = text.splitlines()
    start = next(
        i for i, line in enumerate(lines) if line.startswith(f"{name}() {{")
    )
    # The function body never contains a bare "}" line except its close.
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "}")
    return lines[start : end + 1]


def _extract_helpers() -> str:
    text = RUN_SH.read_text()
    lines = text.splitlines()
    # logfile() and logerr() are single-line definitions.
    logfile = next(l for l in lines if l.startswith("logfile() {"))
    logerr = next(l for l in lines if l.startswith("logerr() {"))
    mapping_file = "\n".join(_function_lines(text, "mapping_file_for"))
    mapping = "\n".join(_function_lines(text, "mapping_for_build"))
    return "\n".join([logfile, logerr, mapping_file, mapping])


def _run_mapping(map_contents: str | None) -> tuple[int, str, str]:
    """Run mapping_for_build with a fake STATE dir; return (rc, stdout, stderr)."""
    with tempfile.TemporaryDirectory() as tmp:
        state = Path(tmp) / "state"
        state.mkdir()
        if map_contents is not None:
            import hashlib

            safe = "".join(
                c if c.isalnum() else "_" for c in "Test Target"
            )
            digest = hashlib.sha256(b"Test Target").hexdigest()[:12]
            (state / ("sort-mapping-" + safe + "-" + digest + ".txt")).write_text(
                map_contents
            )
        harness = textwrap.dedent(
            f"""\
            STATE={state}
            LOG={state}/run.log
            {_extract_helpers()}
            out="$(mapping_for_build 'Test Target')"
            rc=$?
            printf 'RC=%s\\n' "$rc"
            printf 'OUT=[%s]\\n' "$out"
            exit "$rc"
            """
        )
        proc = subprocess.run(
            ["bash", "-c", harness],
            capture_output=True,
            text=True,
            timeout=30,
        )
        # bash -c with `exit "$rc"` reports the function's exit code.
        stdout = proc.stdout
        rc_line = next(
            (l for l in stdout.splitlines() if l.startswith("RC=")), "RC=?"
        )
        out_line = next(
            (l for l in stdout.splitlines() if l.startswith("OUT=")), "OUT=?"
        )
        return int(rc_line[3:]), out_line[5:-1], proc.stderr


class MappingStderrTests(unittest.TestCase):
    def test_no_mapping_file_fails_on_stderr_not_stdout(self):
        rc, out, err = _run_mapping(None)
        self.assertNotEqual(rc, 0)
        self.assertEqual(out, "")
        self.assertIn("GATE FAILED", err)
        self.assertIn("sortprobe", err)

    def test_bad_mapping_word_fails_on_stderr_not_stdout(self):
        rc, out, err = _run_mapping(
            "MAPPING: sideways\nTHROWAWAY: T\nTIMESTAMP: %d\n" % int(time.time())
        )
        self.assertNotEqual(rc, 0)
        self.assertEqual(out, "")
        self.assertIn("GATE FAILED", err)

    def test_bad_timestamp_fails_on_stderr_not_stdout(self):
        rc, out, err = _run_mapping(
            "MAPPING: reversed\nTHROWAWAY: T\nTIMESTAMP: not-a-number\n"
        )
        self.assertNotEqual(rc, 0)
        self.assertEqual(out, "")
        self.assertIn("GATE FAILED", err)

    def test_stale_mapping_fails_on_stderr_not_stdout(self):
        rc, out, err = _run_mapping(
            "MAPPING: forward\nTHROWAWAY: T\nTARGET: Test Target\nSORT: Playlist Order descending\nTIMESTAMP: %d\n"
            % (int(time.time()) - 180000)
        )
        self.assertNotEqual(rc, 0)
        self.assertEqual(out, "")
        self.assertIn("GATE FAILED", err)
        self.assertIn("48 hours", err)

    def test_valid_mapping_captures_exactly_with_quiet_stderr(self):
        rc, out, err = _run_mapping(
            "MAPPING: reversed\nTHROWAWAY: T\nTARGET: Test Target\nSORT: Playlist Order descending\nTIMESTAMP: %d\n" % int(time.time())
        )
        self.assertEqual(rc, 0)
        self.assertEqual(out, "reversed")
        self.assertEqual(err, "")

    def test_no_stdout_pollution_in_captured_functions(self):
        text = RUN_SH.read_text()
        for name in ("mapping_for_build", "probe_mode"):
            body = "\n".join(_function_lines(text, name))
            # A bare log() call (tee to stdout) inside a captured
            # function is the .1 bug; logfile/logerr are the only
            # allowed log calls there.
            self.assertNotIn("\n  log ", "\n" + body)
            self.assertNotIn(" log ", body.replace("logfile", "").replace("logerr", ""))
        # Both captured functions route failures through logerr.
        mapping_body = "\n".join(_function_lines(text, "mapping_for_build"))
        probe_body = "\n".join(_function_lines(text, "probe_mode"))
        self.assertIn("logerr \"GATE FAILED", mapping_body)
        self.assertIn("logerr \"GATE FAILED", probe_body)
        # logerr itself must write to stderr and to the log file,
        # never to plain stdout.
        logerr = next(
            l for l in text.splitlines() if l.startswith("logerr() {")
        )
        self.assertIn(">&2", logerr)
        self.assertIn('tee -a "$LOG"', logerr)


if __name__ == "__main__":
    unittest.main()
