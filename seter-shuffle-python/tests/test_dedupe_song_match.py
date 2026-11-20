"""Same-song dedupe (v3.0.6): ID dedupe alone left one song stored as two
library tracks (two persistent IDs) in the playlist."""

from __future__ import annotations

import io
import json
import os
import random
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from seter_shuffle.cli import main as cli_main
from seter_shuffle.tracks import Track, load_library, split_duplicates, track_from_dict
from seter_shuffle.validate import validate_order_file

ROOT = Path(__file__).resolve().parents[1]


def t(pid, artist="A", name="S", dur=None):
    return Track(persistent_id=pid, artist=artist, name=name, duration_seconds=dur)


def ids(tracks):
    return [x.persistent_id for x in tracks]


class SplitDuplicatesTests(unittest.TestCase):
    def test_id_mode_removes_only_same_id(self):
        tracks = [t("1"), t("2"), t("1"), t("3", "A", "S")]
        kept, removed = split_duplicates(tracks, "id")
        self.assertEqual(ids(kept), ["1", "2", "3"])
        self.assertEqual([r[2] for r in removed], ["same ID"])

    def test_doubled_playlist(self):
        base = [t(str(i), f"Artist{i}", f"Song{i}") for i in range(50)]
        for mode in ("id", "song"):
            kept, removed = split_duplicates(base + base, mode)
            self.assertEqual(ids(kept), ids(base))
            self.assertEqual(len(removed), 50)

    def test_song_mode_merges_different_ids_first_wins(self):
        tracks = [t("a", "Noor", "Quiet Room"), t("b", "Vector", "Drive"), t("c", "Noor", "Quiet Room")]
        kept, removed = split_duplicates(tracks, "song")
        self.assertEqual(ids(kept), ["a", "b"])
        self.assertEqual((removed[0][0].persistent_id, removed[0][1].persistent_id, removed[0][2]), ("c", "a", "same song"))

    def test_normalisation_case_space_unicode(self):
        tracks = [
            t("a", "Beyoncé", "Halo"),
            t("b", "BEYONCE\u0301", "  halo "),   # decomposed accent, case, spaces
            t("c", "Ｂeyoncé", "Halo"),          # full-width B (NFKC)
        ]
        kept, _ = split_duplicates(tracks, "song")
        self.assertEqual(ids(kept), ["a"])

    def test_different_titles_are_never_merged(self):
        tracks = [t("a", "X", "Song"), t("b", "X", "Song (Live)"), t("c", "X", "Song - Remastered 2011")]
        kept, _ = split_duplicates(tracks, "song")
        self.assertEqual(ids(kept), ["a", "b", "c"])

    def test_different_artist_not_merged(self):
        kept, _ = split_duplicates([t("a", "X", "Intro"), t("b", "Y", "Intro")], "song")
        self.assertEqual(ids(kept), ["a", "b"])

    def test_missing_artist_or_title_never_matched_by_name(self):
        tracks = [t("a", "", "Intro"), t("b", "", "Intro"), t("c", "X", ""), t("d", "X", "")]
        kept, _ = split_duplicates(tracks, "song")
        self.assertEqual(ids(kept), ["a", "b", "c", "d"])

    def test_duration_separates_live_from_studio(self):
        tracks = [t("a", "X", "Hurt", 217.0), t("b", "X", "Hurt", 301.0), t("c", "X", "Hurt", 218.5)]
        kept, removed = split_duplicates(tracks, "song")
        self.assertEqual(ids(kept), ["a", "b"])
        self.assertEqual(removed[0][0].persistent_id, "c")

    def test_unknown_duration_matches_on_names(self):
        kept, _ = split_duplicates([t("a", "X", "S", 200.0), t("b", "X", "S", None)], "song")
        self.assertEqual(ids(kept), ["a"])

    def test_removed_id_reappearing_is_still_removed(self):
        tracks = [t("a", "X", "S", 200.0), t("b", "X", "S", 200.0), t("b", "X", "S", 200.0)]
        kept, removed = split_duplicates(tracks, "song")
        self.assertEqual(ids(kept), ["a"])
        self.assertEqual(len(removed), 2)

    def test_bad_mode_raises(self):
        with self.assertRaises(ValueError):
            split_duplicates([t("a")], "title")

    def test_random_playlists_invariants(self):
        rng = random.Random(7)
        for _ in range(300):
            n = rng.randrange(0, 60)
            tracks = [
                t(str(rng.randrange(20)), rng.choice(["A", "a ", "B", ""]),
                  rng.choice(["S", "s", "T", ""]), rng.choice([None, 100.0, 101.0, 200.0]))
                for _ in range(n)
            ]
            # Same ID always means the same track record, as in a real dump.
            canon = {}
            tracks = [canon.setdefault(x.persistent_id, x) for x in tracks]
            snapshot = [(x.persistent_id, x.artist, x.name) for x in tracks]
            for mode in ("id", "song"):
                kept, removed = split_duplicates(tracks, mode)
                self.assertEqual(len(kept) + len(removed), len(tracks))
                self.assertEqual(len(set(ids(kept))), len(kept))
                self.assertTrue(set(ids(kept)) <= {x.persistent_id for x in tracks})
                # Every distinct ID is represented, in first-appearance order.
                firsts = list(dict.fromkeys(ids(tracks)))
                kept_positions = [firsts.index(i) for i in ids(kept)]
                self.assertEqual(kept_positions, sorted(kept_positions))
                # Idempotent: deduping the result removes nothing more.
                again, more = split_duplicates(kept, mode)
                self.assertEqual(ids(again), ids(kept))
                self.assertEqual(more, [])
            kid, _ = split_duplicates(tracks, "id")
            ksong, _ = split_duplicates(tracks, "song")
            self.assertTrue(len(ksong) <= len(kid))
            self.assertEqual(snapshot, [(x.persistent_id, x.artist, x.name) for x in tracks])


class DurationParsingTests(unittest.TestCase):
    def test_duration_ms(self):
        self.assertAlmostEqual(track_from_dict({"persistent_id": "a", "duration_ms": 215373}).duration_seconds, 215.373)

    def test_missing_zero_negative_unknown(self):
        for rec in ({}, {"duration_ms": None}, {"duration_ms": 0}, {"duration_ms": -5}, {"duration_ms": "x"}):
            rec = {"persistent_id": "a", **rec}
            self.assertIsNone(track_from_dict(rec).duration_seconds)


class CliAndValidateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        recs = [
            {"persistent_id": "A1", "name": "Quiet Room", "artist": "Noor", "album": "LP", "duration_ms": 200000},
            {"persistent_id": "B1", "name": "Drive", "artist": "Vector", "duration_ms": 180000},
            {"persistent_id": "A2", "name": "quiet room", "artist": "NOOR", "album": "Single", "duration_ms": 200500},
            {"persistent_id": "B1", "name": "Drive", "artist": "Vector", "duration_ms": 180000},
            {"persistent_id": "C1", "name": "Quiet Room", "artist": "Noor", "duration_ms": 330000},
        ]
        self.lib = self.dir / "lib.json"
        self.lib.write_text(json.dumps({"tracks": recs}))

    def tearDown(self):
        self.tmp.cleanup()

    def run_dedupe(self, *extra):
        out, txt = self.dir / "o.json", self.dir / "o.txt"
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = cli_main(["dedupe", "--library", str(self.lib), "--out", str(out), "--order-txt", str(txt), *extra])
        self.assertEqual(rc, 0)
        return txt.read_text().split(), out, txt, buf.getvalue()

    def test_default_is_song_match(self):
        order, _, _, text = self.run_dedupe()
        self.assertEqual(order, ["A1", "B1", "C1"])  # C1 is 5:30: a different (live?) version
        self.assertIn("(same song)", text)
        self.assertIn("(same ID)", text)

    def test_id_match_leaves_same_song_and_says_so(self):
        order, _, _, text = self.run_dedupe("--match", "id")
        self.assertEqual(order, ["A1", "B1", "A2", "C1"])
        self.assertIn("Note: 1 more entry looks like the same song", text)

    def test_validate_accepts_matching_rule_and_rejects_mismatch(self):
        order, out, txt, _ = self.run_dedupe()
        validate_order_file(self.lib, txt, out, mode="dedupe", dedupe_match="song")
        with self.assertRaises(ValueError):  # id-rule says A2 must stay
            validate_order_file(self.lib, txt, out, mode="dedupe", dedupe_match="id")

    def test_validate_rejects_dropped_distinct_song_and_kept_duplicate(self):
        _, out, txt, _ = self.run_dedupe()
        for bad in (["A1", "B1"], ["A1", "B1", "C1", "A2"], ["B1", "A1", "C1"], ["A1", "A1", "B1", "C1"]):
            txt.write_text("\n".join(bad) + "\n")
            with self.assertRaises(ValueError, msg=str(bad)):
                validate_order_file(self.lib, txt, None, mode="dedupe", dedupe_match="song")

    def test_dump_without_duration_still_loads(self):
        recs = json.loads(self.lib.read_text())["tracks"]
        for r in recs:
            r.pop("duration_ms")
        self.lib.write_text(json.dumps({"tracks": recs}))
        self.assertEqual(len(load_library(self.lib, allow_duplicates=True)), 5)
        order, *_ = self.run_dedupe()
        self.assertEqual(order, ["A1", "B1"])  # C1 now matches by name alone


class RunnerOptionTests(unittest.TestCase):
    def test_bad_match_env_is_refused(self):
        env = dict(os.environ, SETER_DEDUPE_MATCH="title", SETER_TEST_MODE="1")
        out = subprocess.run(["bash", str(ROOT / "run.sh"), "audit"], capture_output=True, text=True, env=env, timeout=30)
        self.assertEqual(out.returncode, 2)
        self.assertIn("SETER_DEDUPE_MATCH", out.stderr)

    def test_dump_script_writes_duration_ms(self):
        text = (ROOT / "bridge" / "dump-library.applescript").read_text()
        self.assertIn("duration_ms", text)
        self.assertIn("jsonDurationMs", text)
        self.assertIn("on jsonDurationMs", text)


if __name__ == "__main__":
    unittest.main()


class RediscoverSameSongTests(unittest.TestCase):
    def test_same_song_two_ids_takes_one_slot(self):
        from datetime import datetime, timezone

        from seter_shuffle.rediscover import pick_rediscover
        from seter_shuffle.settings import Settings

        now = datetime(2026, 10, 29, tzinfo=timezone.utc)
        old = datetime(2020, 1, 1, tzinfo=timezone.utc)
        tracks = [
            Track(persistent_id=f"id{i}", artist=f"Artist{i}", name=f"Song{i}",
                  played_count=10, played_date=old, date_added=old, rating=100)
            for i in range(40)
        ]
        # a second library copy of Song0 under another ID
        tracks.append(Track(persistent_id="dupe", artist="ARTIST0", name="song0",
                            played_count=10, played_date=old, date_added=old, rating=100))
        picked, candidates, _ = pick_rediscover(tracks, now, Settings(), (), random.Random(3))
        names = [(x.artist.lower(), x.name.lower()) for x in picked]
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(candidates, 40)
