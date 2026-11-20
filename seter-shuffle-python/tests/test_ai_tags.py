"""AI tagging: validation, cache, fm client and FlowTagger, with a fake `fm`.

No test needs a Mac or a real `fm`: subprocess calls go through an
injected runner, plus one CLI test that puts a fake `fm` script on PATH.
"""

from __future__ import annotations

import json
import os
import random
import stat
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from seter_shuffle.ai_tags import (
    AiUnavailable,
    FlowTagger,
    FmClient,
    TagCache,
    build_prompt,
    selftest,
    track_signature,
    validate_tags,
)
from seter_shuffle.flow import AiTag, flow_order, mood_cost, prepare_flow
from seter_shuffle.settings import Settings
from seter_shuffle.tracks import Track

ITEM_SCHEMA = '{"type":"object","properties":{"n":{"type":"integer"},"energy":{"type":"integer"},"mood":{"type":"string"}}}'
BATCH_SCHEMA = '{"type":"object","properties":{"tags":{"type":"array","items":' + ITEM_SCHEMA + "}}}"


def tr(pid, name=None, artist="A", genre="Pop", year=2020, bpm=None, **kw):
    return Track(persistent_id=pid, name=name or pid, artist=artist, genre=genre, year=year, bpm=bpm, **kw)


class FakeFm:
    """Runner standing in for `fm`: answers schema and respond calls."""

    def __init__(self, energy=lambda n, line: 50 + n, mood="upbeat", mode="ok"):
        self.calls = []
        self.energy, self.mood, self.mode = energy, mood, mode
        self.respond_calls = 0

    def __call__(self, argv, stdin):
        self.calls.append((list(argv), stdin))
        if argv[1] == "schema":
            if "--array" in argv:
                return 0, BATCH_SCHEMA, ""
            return 0, ITEM_SCHEMA, ""
        self.respond_calls += 1
        if self.mode == "license":
            return 1, "", "You must accept the license: sudo fm license"
        if self.mode == "fail":
            return 1, "", "boom"
        lines = [l for l in stdin.splitlines() if l.strip()]
        tags = []
        for line in lines:
            n = int(line.split("|")[0])
            tags.append({"n": n, "energy": self.energy(n, line), "mood": self.mood})
        if self.mode == "drop_last" and len(tags) > 1:
            tags = tags[:-1]
        if self.mode == "dup_first" and len(tags) > 1:
            tags.append(dict(tags[0]))
        if "--schema" in argv and Path(argv[argv.index("--schema") + 1]).name.startswith("item"):
            return 0, json.dumps(tags[0]), ""
        if self.mode == "fenced":
            return 0, "```json\n" + json.dumps({"tags": tags}) + "\n```", ""
        return 0, json.dumps({"tags": tags}), ""


class ValidateTagsTests(unittest.TestCase):
    def test_accepts_wrapped_list_bare_list_and_fences(self):
        good = [{"n": 1, "energy": 70, "mood": "Driving"}, {"n": 2, "energy": "20", "mood": "calm"}]
        for text in (json.dumps({"tags": good}), json.dumps(good), "```json\n" + json.dumps(good) + "\n```",
                     "Here you go: " + json.dumps(good) + " done"):
            got = validate_tags(text, [1, 2])
            self.assertEqual(got[1], AiTag(70, "driving"), text)
            self.assertEqual(got[2], AiTag(20, "calm"), text)

    def test_clamps_energy_and_drops_bad_mood_but_keeps_energy(self):
        got = validate_tags(json.dumps([{"n": 1, "energy": 250, "mood": "spooky"}, {"n": 2, "energy": -5}]), [1, 2])
        self.assertEqual(got[1], AiTag(100, None))
        self.assertEqual(got[2], AiTag(0, None))

    def test_unknown_missing_duplicate_and_nonnumeric_are_absent(self):
        data = [
            {"n": 1, "energy": 10}, {"n": 1, "energy": 90},  # duplicate n
            {"n": 2, "energy": "loud"},                        # not numeric
            {"n": 9, "energy": 50},                            # never sent
            {"energy": 40},                                    # no n, several expected
            {"n": True, "energy": 5},                          # bool is not a number
        ]
        self.assertEqual(validate_tags(json.dumps(data), [1, 2, 3]), {})

    def test_single_song_reply_may_omit_n(self):
        self.assertEqual(validate_tags('{"energy": 33, "mood": "mellow"}', [1]), {1: AiTag(33, "mellow")})

    def test_not_json_raises(self):
        with self.assertRaises(ValueError):
            validate_tags("I cannot help with that.", [1])
        with self.assertRaises(ValueError):
            validate_tags('"just a string"', [1])


class PromptTests(unittest.TestCase):
    def test_prompt_lines_are_numbered_and_sanitised(self):
        t = [tr("x", name="Pipe|Name\nLine", artist="Ar", genre="G", year=1999, bpm=120.0), tr("y", year=None)]
        lines = build_prompt(t).split("\n")
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[0], "1|Pipe Name Line|Ar|G|1999|120")
        self.assertTrue(lines[1].startswith("2|y|A|Pop||"))

    def test_signature_tracks_metadata_changes(self):
        a = tr("p", genre="Rock")
        self.assertEqual(track_signature(a), track_signature(tr("p", genre="Rock")))
        self.assertNotEqual(track_signature(a), track_signature(tr("p", genre="Jazz")))


class CacheTests(unittest.TestCase):
    def test_roundtrip_and_signature_invalidation(self):
        with tempfile.TemporaryDirectory() as d:
            c = TagCache(Path(d) / "ai-tags.json")
            t = tr("p1", genre="Rock")
            self.assertIsNone(c.get(t))
            c.put(t, AiTag(77, "dark"))
            c.save()
            again = TagCache(Path(d) / "ai-tags.json")
            self.assertEqual(again.get(t), AiTag(77, "dark"))
            self.assertIsNone(again.get(tr("p1", genre="Jazz")))  # metadata changed: retag

    def test_corrupt_cache_is_quarantined_not_fatal(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "ai-tags.json"
            path.write_text("{not json", encoding="utf-8")
            c = TagCache(path)
            self.assertEqual(c.entries, {})
            self.assertTrue((Path(d) / "ai-tags.json.bad").exists())
            c.put(tr("a"), AiTag(1))
            c.save()  # a fresh cache can be written afterwards
            self.assertEqual(TagCache(path).get(tr("a")), AiTag(1))

    def test_save_leaves_no_temp_files(self):
        with tempfile.TemporaryDirectory() as d:
            c = TagCache(Path(d) / "ai-tags.json")
            c.put(tr("a"), AiTag(1)); c.save(); c.save()
            self.assertEqual(sorted(p.name for p in Path(d).iterdir()), ["ai-tags.json"])


class ClientAndTaggerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def tagger(self, fm, **kw):
        client = FmClient(self.dir, runner=fm)
        return FlowTagger(TagCache(self.dir / "ai-tags.json"), client, log=lambda m: None, **kw)

    def test_batches_tag_everything_and_cache_prevents_repeat_calls(self):
        fm = FakeFm()
        tracks = [tr(f"t{i}") for i in range(45)]
        tagger = self.tagger(fm, batch_size=20)
        out = tagger(tracks)
        self.assertEqual(len(out), 45)
        self.assertEqual(fm.respond_calls, 3)  # 20 + 20 + 5
        # second run: everything cached, no respond calls at all
        fm2 = FakeFm()
        out2 = self.tagger(fm2, batch_size=20)(tracks)
        self.assertEqual(out2, out)
        self.assertEqual(fm2.respond_calls, 0)

    def test_command_line_uses_documented_flags(self):
        fm = FakeFm()
        self.tagger(fm)([tr("a"), tr("b")])
        argv = next(c for c, _ in fm.calls if c[1] == "respond")
        for flag in ("--use-case", "content-tagging", "--greedy", "--no-stream", "--schema", "--instructions"):
            self.assertIn(flag, argv)
        self.assertNotIn("--model", argv)  # on-device default, nothing leaves the Mac

    def test_dropped_song_is_retried_alone(self):
        fm = FakeFm(mode="drop_last")
        out = self.tagger(fm, batch_size=5)([tr(f"t{i}") for i in range(5)])
        self.assertEqual(len(out), 5)
        self.assertEqual(fm.respond_calls, 2)  # one batch + one single retry

    def test_duplicate_n_in_reply_is_not_trusted_and_is_retried(self):
        fm = FakeFm(mode="dup_first")
        out = self.tagger(fm, batch_size=4)([tr(f"t{i}") for i in range(4)])
        self.assertEqual(len(out), 4)
        self.assertGreaterEqual(fm.respond_calls, 2)

    def test_code_fenced_reply_works(self):
        out = self.tagger(FakeFm(mode="fenced"), batch_size=3)([tr("a"), tr("b"), tr("c")])
        self.assertEqual(len(out), 3)

    def test_license_error_stops_cleanly_and_tags_nothing(self):
        fm = FakeFm(mode="license")
        t = self.tagger(fm, batch_size=10)
        self.assertEqual(t([tr(f"t{i}") for i in range(30)]), {})
        self.assertIn("sudo fm license", t.stopped)
        self.assertEqual(fm.respond_calls, 1)  # did not hammer fm

    def test_consecutive_failures_stop_the_run(self):
        fm = FakeFm(mode="fail")
        t = self.tagger(fm, batch_size=2, max_consecutive_failures=2)
        self.assertEqual(t([tr(f"t{i}") for i in range(40)]), {})
        self.assertIn("failures in a row", t.stopped)
        self.assertLess(fm.respond_calls, 20)

    def test_time_budget_stops_and_keeps_what_was_tagged(self):
        fm = FakeFm()
        now = [0.0]
        def clock():
            now[0] += 100.0  # every check costs 100 "seconds"
            return now[0]
        t = self.tagger(fm, batch_size=5, time_budget=250.0, clock=clock)
        out = t([tr(f"t{i}") for i in range(50)])
        self.assertIn("time budget", t.stopped)
        self.assertLess(len(out), 50)
        # whatever was tagged before the stop is on disk
        self.assertEqual(len(TagCache(self.dir / "ai-tags.json").entries), len(out))

    def test_no_array_schema_falls_back_to_one_song_per_call(self):
        class NoArray(FakeFm):
            def __call__(self, argv, stdin):
                if argv[1] == "schema" and "--array" in argv:
                    return 1, "", "unknown option --array"
                return super().__call__(argv, stdin)
        fm = NoArray()
        out = self.tagger(fm, batch_size=20)([tr(f"t{i}") for i in range(3)])
        self.assertEqual(len(out), 3)
        self.assertEqual(fm.respond_calls, 3)

    def test_int_flag_fallback(self):
        class IntOnly(FakeFm):
            def __call__(self, argv, stdin):
                if argv[1] == "schema" and "--integer" in argv:
                    return 2, "", "unknown option '--integer'"
                return super().__call__(argv, stdin)
        out = self.tagger(IntOnly())([tr("a"), tr("b")])
        self.assertEqual(len(out), 2)

    def test_missing_fm_binary_is_unavailable(self):
        client = FmClient(self.dir, fm="definitely-not-installed-fm")
        t = FlowTagger(TagCache(self.dir / "c.json"), client, log=lambda m: None)
        self.assertEqual(t([tr("a")]), {})
        self.assertIn("not found", t.stopped)

    def test_guardrail_refusal_retries_permissively(self):
        class Guard(FakeFm):
            def __call__(self, argv, stdin):
                if argv[1] == "respond" and "--guardrails" not in argv:
                    self.respond_calls += 1
                    return 1, "", "Guardrail violation"
                return super().__call__(argv, stdin)
        fm = Guard()
        out = self.tagger(fm, batch_size=2)([tr("a"), tr("b")])
        self.assertEqual(len(out), 2)

    def test_selftest_reports_ok_and_failure(self):
        lines = []
        self.assertTrue(selftest(FmClient(self.dir, runner=FakeFm()), out=lines.append))
        self.assertTrue(any("OK" in l for l in lines))
        lines = []
        self.assertFalse(selftest(FmClient(self.dir / "x", runner=FakeFm(mode="fail")), out=lines.append))
        self.assertTrue(any(l.startswith("FAIL") for l in lines))


class FlowIntegrationTests(unittest.TestCase):
    NOW = datetime(2026, 10, 28, tzinfo=timezone.utc)

    def library(self, n=60):
        return [tr(f"t{i}", artist=f"Artist {i}", genre=("Rock", "Pop", "Jazz")[i % 3], year=1990 + i % 30,
                   bpm=float(80 + i), played_count=i % 5) for i in range(n)]

    def settings(self, **kw):
        return Settings(flow_size=30, flow_pool_max=60, **kw)

    def test_ai_disabled_or_no_tagger_is_identical_to_baseline(self):
        lib = self.library()
        base = prepare_flow(lib, self.settings(), random.Random(5), self.NOW)
        called = []
        def tagger(tracks):
            called.append(1); return {}
        off = prepare_flow(lib, self.settings(ai_enabled=False), random.Random(5), self.NOW, tagger=tagger)
        self.assertEqual(called, [])  # never invoked when disabled
        self.assertEqual([t.persistent_id for t in off[0]], [t.persistent_id for t in base[0]])
        empty = prepare_flow(lib, self.settings(ai_enabled=True), random.Random(5), self.NOW, tagger=lambda ts: {})
        self.assertEqual([t.persistent_id for t in empty[0]], [t.persistent_id for t in base[0]])
        self.assertEqual(empty[1], base[1])

    def test_tagger_only_sees_pool_and_blends_energy(self):
        lib = self.library()
        seen = []
        def tagger(tracks):
            seen.extend(t.persistent_id for t in tracks)
            return {t.persistent_id: AiTag(100, "euphoric") for t in tracks}
        s = Settings(flow_size=20, flow_pool_max=25, ai_enabled=True, ai_blend=1.0)
        ordered, energies, _ = prepare_flow(lib, s, random.Random(1), self.NOW, tagger=tagger)
        self.assertEqual(len(seen), 25)  # pool only, not all 60
        self.assertTrue(all(e == 100 for e in energies))  # blend 1.0 = pure AI

    def test_blend_math_and_clamp(self):
        lib = [tr("only", bpm=100.0)]
        base = prepare_flow(lib, Settings(flow_size=1, ai_enabled=False), random.Random(1), self.NOW)[1][0]
        s = Settings(flow_size=1, ai_enabled=True, ai_blend=0.5)
        got = prepare_flow(lib, s, random.Random(1), self.NOW, tagger=lambda ts: {"only": AiTag(0)})[1][0]
        self.assertEqual(got, max(5, round(0.5 * 0 + 0.5 * base)))

    def test_tagger_exception_never_fails_flow(self):
        def boom(tracks):
            raise RuntimeError("model exploded")
        lib = self.library()
        ordered, _e, _n = prepare_flow(lib, self.settings(ai_enabled=True), random.Random(2), self.NOW, tagger=boom)
        self.assertEqual(len(ordered), 30)

    def test_mood_cost_shape(self):
        self.assertEqual(mood_cost("calm", "calm", 4), 0)
        self.assertEqual(mood_cost("calm", "mellow", 4), 2.0)
        self.assertEqual(mood_cost("calm", "driving", 4), 4.0)
        self.assertEqual(mood_cost(None, "driving", 4), 0)
        self.assertEqual(mood_cost("calm", "driving", 0), 0)

    def test_mood_continuity_changes_the_walk(self):
        # identical energy/genre/year everywhere: only mood can break ties,
        # so a heavy mood weight must group songs of the same mood.
        n = 12
        energies = [50] * n
        genres = ["pop"] * n
        years = [2020] * n
        keys = [f"artist{i}" for i in range(n)]
        moods = ["calm", "dark"] * (n // 2)
        order = flow_order(energies, genres, years, keys, total=n, spacing=0, moods=moods, mood_weight=50)
        seq = [moods[i] for i in order]
        switches = sum(1 for a, b in zip(seq, seq[1:]) if a != b)
        self.assertLessEqual(switches, 3, seq)


class CliTests(unittest.TestCase):
    """Real subprocess path: a fake `fm` script on PATH."""

    FAKE_FM = r'''#!/usr/bin/env python3
import json, sys
a = sys.argv[1:]
if a[0] == "schema":
    item = {"type": "object", "properties": {"n": {"type": "integer"}, "energy": {"type": "integer"}, "mood": {"type": "string"}}}
    out = {"type": "object", "properties": {"tags": {"type": "array", "items": item}}} if "--array" in a else item
    print(json.dumps(out)); sys.exit(0)
rows = [l for l in sys.stdin.read().splitlines() if l.strip()]
tags = [{"n": int(r.split("|")[0]), "energy": 90, "mood": "driving"} for r in rows]
print(json.dumps({"tags": tags}) if "batch" in a[a.index("--schema") + 1] else json.dumps(tags[0]))
'''

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        d = Path(self.tmp.name)
        (d / "bin").mkdir()
        fm = d / "bin" / "fm"
        fm.write_text(self.FAKE_FM, encoding="utf-8")
        fm.chmod(fm.stat().st_mode | stat.S_IXUSR)
        lib = [
            {"persistent_id": f"t{i}", "name": f"Song {i}", "artist": f"Artist {i}", "genre": "Pop",
             "year": 2000 + i % 20, "bpm": 100 + i, "played_count": i % 4,
             "played_date": "2020-01-01T00:00:00Z", "date_added": "2019-01-01T00:00:00Z"}
            for i in range(40)
        ]
        self.lib = d / "lib.json"
        self.lib.write_text(json.dumps({"tracks": lib}), encoding="utf-8")
        self.env = dict(os.environ, PATH=f"{d / 'bin'}{os.pathsep}{os.environ['PATH']}",
                        SETER_AI_DIR=str(d / "ai"), PYTHONPATH=str(ROOT))
        self.env.pop("SETER_AI", None)

    def run_cli(self, *args):
        return subprocess.run([sys.executable, "-m", "seter_shuffle.cli", *args],
                              capture_output=True, text=True, env=self.env, cwd=ROOT)

    def test_selftest_ok(self):
        r = self.run_cli("ai-selftest")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("OK: AI tagging is usable", r.stdout)

    def test_flow_with_ai_writes_cache_and_succeeds(self):
        out = Path(self.tmp.name) / "order.json"
        r = self.run_cli("flow", "--library", str(self.lib), "--out", str(out), "--seed", "3", "--ai", "--flow-size", "20")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("AI tags:", r.stderr)
        self.assertEqual(json.loads(out.read_text())["count"], 20)
        cache = json.loads((Path(self.tmp.name) / "ai" / "ai-tags.json").read_text())
        self.assertGreater(len(cache["entries"]), 0)

    def test_flow_with_ai_but_no_fm_still_succeeds(self):
        self.env["PATH"] = "/usr/bin:/bin"  # fm gone
        r = self.run_cli("flow", "--library", str(self.lib), "--seed", "3", "--ai", "--flow-size", "10")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("AI tagging stopped", r.stderr)

    def test_marker_file_and_env_enable_ai(self):
        marker_dir = Path(self.tmp.name) / "ai"
        marker_dir.mkdir()
        (marker_dir / "ai-enabled").write_text("")
        r = self.run_cli("flow", "--library", str(self.lib), "--seed", "3", "--flow-size", "10")
        self.assertIn("AI tags:", r.stderr)
        r = self.run_cli("flow", "--library", str(self.lib), "--seed", "3", "--flow-size", "10", "--no-ai")
        self.assertNotIn("AI tags:", r.stderr)
        self.env["SETER_AI"] = "0"
        r = self.run_cli("flow", "--library", str(self.lib), "--seed", "3", "--flow-size", "10")
        self.assertNotIn("AI tags:", r.stderr)


if __name__ == "__main__":
    unittest.main()
