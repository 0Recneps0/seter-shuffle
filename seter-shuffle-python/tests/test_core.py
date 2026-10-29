"""Tests for the SeTeR Shuffle Python experimental core.

Standard library unittest only. Run from the project root:
    python3 -m unittest discover -s tests -v

Every test runs against in-memory tracks or the sample fixture; none
touches Music, the network, or any real library. The bridge scripts are
NOT covered here (they need a Mac) and are listed as unverified in the
changelog instead of being faked into passing.
"""

from __future__ import annotations

import hashlib
import json
import random
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.artists import artist_key
from seter_shuffle.audit import audit_library, format_audit
from seter_shuffle.flow import (
    familiarity,
    flow_energy,
    flow_order,
    flow_target_energy,
    genre_group,
    prepare_flow,
)
from seter_shuffle.rediscover import (
    is_rediscover_eligible,
    load_rediscover_history,
    pick_rediscover,
    record_rediscover_history,
    rediscover_target,
    rediscover_weight,
)
from seter_shuffle.settings import Settings
from seter_shuffle.shuffle import fisher_yates, shuffle_tracks, spread_artists
from seter_shuffle.tracks import Track, load_library

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "sample-library.json"
NOW = datetime(2026, 10, 28, tzinfo=timezone.utc)


def make_track(pid: str, **overrides) -> Track:
    base = {
        "persistent_id": pid,
        "name": pid,
        "artist": "Artist",
        "genre": "Pop",
        "bpm": 120,
        "year": 2020,
        "played_count": 5,
        "played_date": datetime(2024, 1, 1, tzinfo=timezone.utc),
        "date_added": datetime(2020, 1, 1, tzinfo=timezone.utc),
    }
    base.update(overrides)
    return Track(**base)


class ArtistKeyTests(unittest.TestCase):
    def test_featuring_counts_as_main_artist(self):
        self.assertEqual(artist_key("Vector feat. Luna"), "Vector")
        self.assertEqual(artist_key("Vector (ft. Luna)"), "Vector")
        self.assertEqual(artist_key("Vector featuring Luna"), "Vector")

    def test_featuring_off_keeps_full_name(self):
        self.assertEqual(
            artist_key("Vector feat. Luna", featuring_is_same_artist=False),
            "Vector feat. Luna",
        )

    def test_plain_names_and_empty_unchanged(self):
        self.assertEqual(artist_key("Noor"), "Noor")
        self.assertEqual(artist_key(""), "")
        self.assertEqual(artist_key(None), "")


class ShuffleTests(unittest.TestCase):
    def test_fisher_yates_preserves_the_set_and_input(self):
        tracks = [make_track(str(i)) for i in range(20)]
        shuffled = fisher_yates(tracks, random.Random(7))
        self.assertEqual(len(shuffled), 20)
        self.assertEqual({t.persistent_id for t in shuffled}, {t.persistent_id for t in tracks})
        self.assertEqual([t.persistent_id for t in tracks], [str(i) for i in range(20)])

    def test_fisher_yates_is_replayable_with_a_seed(self):
        tracks = [make_track(str(i)) for i in range(20)]
        self.assertEqual(
            [t.persistent_id for t in fisher_yates(tracks, random.Random(3))],
            [t.persistent_id for t in fisher_yates(tracks, random.Random(3))],
        )

    def test_spread_artists_separates_when_possible(self):
        # v2.6 spacing semantics: spacing=2 means at least 2 songs
        # between repeats, so a rotation needs 3 distinct artists.
        # A perfectly spaced rotation is left clash-free, and spreading
        # a grouped list never increases the clash count.
        keys = ["A", "B", "C", "A", "B", "C", "A", "B", "C"]
        order = spread_artists(list(range(9)), keys, spacing=2, rng=random.Random(1))
        placed = [keys[i] for i in order]
        for i, key in enumerate(placed):
            for j in range(i + 1, min(i + 3, len(placed))):
                self.assertNotEqual(key, placed[j], f"clash at {i} and {j}: {placed}")

        def clash_count(seq):
            count = 0
            for i, key in enumerate(seq):
                for j in range(i + 1, min(i + 3, len(seq))):
                    if seq[j] == key:
                        count += 1
            return count

        grouped = ["A", "A", "A", "B", "B", "B", "C", "C", "C"]
        spread = spread_artists(
            list(range(9)), grouped, spacing=2, rng=random.Random(1)
        )
        self.assertEqual(sorted(spread), list(range(9)))
        self.assertLessEqual(
            clash_count([grouped[i] for i in spread]), clash_count(grouped)
        )

    def test_spread_artists_is_best_effort_not_infinite(self):
        # One artist owns the whole list: no separation is possible, and
        # the function must still return promptly with all songs.
        keys = ["A"] * 10
        order = spread_artists(list(range(10)), keys, spacing=2, rng=random.Random(1))
        self.assertEqual(sorted(order), list(range(10)))

    def test_shuffle_tracks_respects_featuring(self):
        tracks = [
            make_track("1", artist="Vector"),
            make_track("2", artist="Vector feat. Luna"),
            make_track("3", artist="Noor"),
            make_track("4", artist="Luna"),
            make_track("5", artist="Noor"),
            make_track("6", artist="Vector"),
        ]
        ordered = shuffle_tracks(tracks, spacing=1, rng=random.Random(4))
        keys = [artist_key(t.artist) for t in ordered]
        for i in range(len(keys) - 1):
            self.assertNotEqual(keys[i], keys[i + 1])


class FlowTests(unittest.TestCase):
    def test_energy_missing_bpm_and_genre_defaults_to_mid(self):
        track = make_track("X", bpm=None, genre="", played_count=0, rating=0, favorited=False)
        self.assertEqual(flow_energy(track), 50)

    def test_energy_bpm_bands_and_genre_nudges(self):
        self.assertEqual(flow_energy(make_track("a", bpm=70, genre="Rock", played_count=0)), 33)
        self.assertEqual(flow_energy(make_track("b", bpm=130, genre="Classical", played_count=0)), 63)
        self.assertEqual(flow_energy(make_track("c", bpm=200, genre="", played_count=0)), 95)

    def test_energy_clamps(self):
        high = make_track("h", bpm=200, genre="Rock", played_count=30, rating=100, favorited=True)
        self.assertEqual(flow_energy(high), 100)
        low = make_track("l", bpm=70, genre="Classical", played_count=0, rating=20)
        self.assertEqual(flow_energy(low), 5)

    def test_genre_group_order_and_unknown(self):
        self.assertEqual(genre_group("Punk Rock"), 1)
        self.assertEqual(genre_group("Hip-Hop"), 2)
        self.assertEqual(genre_group("EDM"), 3)
        self.assertEqual(genre_group("Lo-Fi Beats"), 6)
        self.assertEqual(genre_group("K-Pop"), 3)  # substring "pop", as in AppleScript
        self.assertEqual(genre_group(""), 7)
        self.assertEqual(genre_group(None), 7)

    def test_arc_targets(self):
        self.assertEqual(flow_target_energy(1, 1), 50.0)
        self.assertAlmostEqual(flow_target_energy(1, 9), 45.0)
        self.assertAlmostEqual(flow_target_energy(6, 9), 90.0)
        self.assertAlmostEqual(flow_target_energy(9, 9), 40.0)

    def test_flow_empty_library(self):
        ordered, energies, eligible = prepare_flow([], Settings())
        self.assertEqual((ordered, energies, eligible), ([], [], 0))

    def test_flow_single_song(self):
        ordered, energies, eligible = prepare_flow([make_track("only")], Settings())
        self.assertEqual([t.persistent_id for t in ordered], ["only"])
        self.assertEqual(eligible, 1)
        self.assertEqual(len(energies), 1)

    def test_flow_two_songs_ends_at_peak(self):
        # Documented AppleScript quirk, preserved: a 2-song arc has no
        # fall, so the second target is the peak (90), not the end (40).
        self.assertAlmostEqual(flow_target_energy(2, 2), 90.0)
        tracks = [make_track("a", bpm=70), make_track("b", bpm=160)]
        ordered, _, eligible = prepare_flow(tracks, Settings(flow_size=2))
        self.assertEqual(len(ordered), 2)
        self.assertEqual(eligible, 2)

    def test_flow_excludes_disliked_and_unchecked_but_not_skip_heavy(self):
        tracks = [
            make_track("ok", bpm=120),
            make_track("bad", bpm=120, disliked=True),
            make_track("off", bpm=120, enabled=False),
            make_track("skippy", bpm=120, played_count=1, skipped_count=9),
        ]
        ordered, _, eligible = prepare_flow(tracks, Settings())
        self.assertEqual(
            {t.persistent_id for t in ordered}, {"ok", "skippy"}
        )
        self.assertEqual(eligible, 2)

    def test_flow_artist_spacing_wins_over_vibe(self):
        tracks = [
            make_track("a1", artist="A", bpm=120, genre="Pop", year=2020),
            make_track("a2", artist="A", bpm=120, genre="Pop", year=2020),
            make_track("b1", artist="B", bpm=120, genre="Pop", year=2020),
            make_track("c1", artist="C", bpm=120, genre="Pop", year=2020),
        ]
        ordered, _, _ = prepare_flow(tracks, Settings(flow_size=4))
        keys = [artist_key(t.artist) for t in ordered]
        for i in range(len(keys) - 1):
            # spacing=2 forbids the same artist within 2 positions after.
            for j in range(i + 1, min(i + 3, len(keys))):
                self.assertNotEqual(keys[i], keys[j])

    def test_flow_order_ties_keep_earliest(self):
        energies = [50, 50, 50]
        groups = [7, 7, 7]
        years = [None, None, None]
        keys = ["", "", ""]
        self.assertEqual(flow_order(energies, groups, years, keys, 3, spacing=2), [0, 1, 2])


class RediscoverTests(unittest.TestCase):
    def test_target_clamps(self):
        settings = Settings(rediscover_percent=1, rediscover_min=30, rediscover_max=500)
        self.assertEqual(rediscover_target(100, settings), 30)
        self.assertEqual(rediscover_target(100000, settings), 500)
        self.assertEqual(rediscover_target(5000, settings), 50)

    def test_eligibility_exclusions(self):
        settings = Settings()
        base = make_track("x")
        self.assertTrue(is_rediscover_eligible(base, NOW, settings))
        self.assertFalse(is_rediscover_eligible(make_track("d", disliked=True), NOW, settings))
        self.assertFalse(is_rediscover_eligible(make_track("u", enabled=False), NOW, settings))
        self.assertFalse(
            is_rediscover_eligible(
                make_track("s", played_count=1, skipped_count=9), NOW, settings
            )
        )
        recent = make_track(
            "r", played_count=5, played_date=datetime(2026, 10, 20, tzinfo=timezone.utc)
        )
        self.assertFalse(is_rediscover_eligible(recent, NOW, settings))
        # Skip-heavy threshold: 2 skips is not skip-heavy.
        self.assertTrue(
            is_rediscover_eligible(
                make_track("s2", played_count=1, skipped_count=2), NOW, settings
            )
        )

    def test_weight_formula(self):
        settings = Settings()
        never = make_track("n", played_count=0, date_added=datetime(2020, 1, 1, tzinfo=timezone.utc))
        # 0.4 base x forgotten multiplier capped at 5.
        self.assertAlmostEqual(rediscover_weight(never, NOW, settings), 0.4 * 5)
        loved = make_track(
            "l", played_count=10, favorited=True, rating=100,
            played_date=datetime(2024, 1, 1, tzinfo=timezone.utc),
        )
        # (1 + 10*0.5) x3 x2, divided by 1 skip-free, x forgotten capped at 5.
        self.assertAlmostEqual(rediscover_weight(loved, NOW, settings), 6.0 * 3 * 2 * 5)
        low_rated = make_track(
            "lr", played_count=2, rating=20,
            played_date=datetime(2024, 1, 1, tzinfo=timezone.utc),
        )
        self.assertAlmostEqual(rediscover_weight(low_rated, NOW, settings), 2.0 * 0.25 * 5)

    def test_pick_max_per_artist_and_cooldown(self):
        settings = Settings(rediscover_min=10, rediscover_max=10, rediscover_max_per_artist=2)
        tracks = []
        for artist in ("A", "B", "C", "D", "E", "F"):
            for i in range(3):
                tracks.append(make_track(f"{artist}{i}", artist=artist))
        picked, candidates, target = pick_rediscover(
            tracks, NOW, settings, history_ids={"A0", "A1"}, rng=random.Random(11)
        )
        self.assertEqual(target, 10)
        self.assertEqual(len(picked), 10)
        from collections import Counter

        counts = Counter(artist_key(t.artist) for t in picked)
        # Pass 1 enforces the cap; pass 2 may relax it only if the pool
        # could not fill the target, which it can here.
        self.assertTrue(all(count <= 2 for count in counts.values()))
        self.assertNotIn("A0", [t.persistent_id for t in picked])
        self.assertNotIn("A1", [t.persistent_id for t in picked])

    def test_pick_empty_library(self):
        picked, candidates, target = pick_rediscover([], NOW, Settings(), rng=random.Random(1))
        self.assertEqual((picked, candidates), ([], 0))

    def test_history_load_and_record_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "history.tsv"
            path.write_text("2026-10-01\tOLD1\n2026-10-20\tNEW1\nbadline\n", encoding="utf-8")
            loaded = load_rediscover_history(path, 14, today=datetime(2026, 10, 28).date())
            self.assertEqual(loaded, {"NEW1"})
            record_rediscover_history(
                path, ["PICK1"], 14, today=datetime(2026, 10, 28).date()
            )
            lines = path.read_text(encoding="utf-8").splitlines()
            self.assertIn("2026-10-20\tNEW1", lines)
            self.assertIn("2026-10-28\tPICK1", lines)
            self.assertNotIn("2026-10-01\tOLD1", lines)


class CliTests(unittest.TestCase):
    def run_cli(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, "-m", "seter_shuffle.cli", *args],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )

    def test_flow_preview_changes_nothing(self):
        before = hashlib.sha256(FIXTURE.read_bytes()).hexdigest()
        result = self.run_cli(
            "flowPreview", "--library", str(FIXTURE), "--seed", "42"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Flow:", result.stdout)
        self.assertIn("Nothing was changed.", result.stdout)
        # No --out was given, and the fixture itself must be untouched.
        self.assertEqual(hashlib.sha256(FIXTURE.read_bytes()).hexdigest(), before)

    def test_flow_preview_excludes_disliked_and_unchecked(self):
        result = self.run_cli(
            "flowPreview", "--library", str(FIXTURE), "--seed", "42"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Disliked Song", result.stdout)
        self.assertNotIn("Unchecked Song", result.stdout)
        self.assertIn("Quiet Room", result.stdout)  # missing BPM/genre still included

    def test_rediscover_preview_changes_nothing_and_excludes(self):
        before = hashlib.sha256(FIXTURE.read_bytes()).hexdigest()
        result = self.run_cli(
            "rediscover-preview", "--library", str(FIXTURE), "--seed", "42",
            "--rediscover-min", "3", "--rediscover-max", "3",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Nothing was changed.", result.stdout)
        self.assertNotIn("Skipped Often", result.stdout)
        # "Recent Hit" recency is covered by the fixed-date unit test
        # above; it is deliberately not asserted here, because this CLI
        # test runs against the real clock and the fixture's play date
        # will eventually age past the 60-day stale window.
        self.assertEqual(hashlib.sha256(FIXTURE.read_bytes()).hexdigest(), before)

    def test_shuffle_writes_order_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "order.json"
            txt = Path(tmp) / "order.txt"
            result = self.run_cli(
                "shuffle", "--library", str(FIXTURE), "--seed", "5",
                "--out", str(out), "--order-txt", str(txt),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(len(payload["ids"]), 8)
            self.assertEqual(set(payload["ids"]), {"AAA", "BBB", "CCC", "DDD", "EEE", "FFF", "GGG", "HHH"})
            self.assertEqual(txt.read_text(encoding="utf-8").splitlines(), payload["ids"])

    def test_load_library_rejects_duplicate_ids(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad.json"
            bad.write_text(
                json.dumps({"tracks": [
                    {"persistent_id": "X", "artist": "A"},
                    {"persistent_id": "X", "artist": "B"},
                ]}),
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                load_library(bad)

    def test_record_history_command(self):
        with tempfile.TemporaryDirectory() as tmp:
            history = Path(tmp) / "history.tsv"
            ids = Path(tmp) / "ids.txt"
            ids.write_text("AAA\nBBB\n", encoding="utf-8")
            result = self.run_cli(
                "record-history", "--history", str(history),
                "--ids-file", str(ids), "--today", "2026-10-28",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("2026-10-28\tAAA", history.read_text(encoding="utf-8"))


class MissingBpmFallbackTests(unittest.TestCase):
    def missing_bpm_cases(self):
        return [
            ("gospel-never", dict(genre="Gospel", played_count=0, rating=0, favorited=False, skipped_count=0)),
            ("gospel-loved", dict(genre="Christian", played_count=40, rating=100, favorited=True, skipped_count=0)),
            ("pop-often", dict(genre="Pop", played_count=25, rating=0, favorited=False, skipped_count=0)),
            ("pop-never", dict(genre="Pop", played_count=0, rating=0, favorited=False, skipped_count=0)),
            ("rock-skippy", dict(genre="Rock", played_count=2, rating=0, favorited=False, skipped_count=8)),
            ("ambient-never", dict(genre="Ambient", played_count=0, rating=0, favorited=False, skipped_count=0)),
            ("worship-mid", dict(genre="Worship", played_count=8, rating=80, favorited=False, skipped_count=0)),
            ("unknown-never", dict(genre="", played_count=0, rating=0, favorited=False, skipped_count=0)),
            ("unknown-loved", dict(genre="", played_count=60, rating=100, favorited=True, skipped_count=0)),
            ("latin-often", dict(genre="Reggaeton", played_count=15, rating=0, favorited=False, skipped_count=0)),
        ]

    def test_missing_bpm_songs_spread_instead_of_clumping_at_50(self):
        energies = []
        for name, kw in self.missing_bpm_cases():
            track = make_track(name, bpm=None, **kw)
            energies.append(flow_energy(track))
        # Old model gave only 6 distinct values, three of them exactly
        # 50 (gospel-never, latin-often, unknown-never). The fallback
        # must spread them without inventing a tempo-wide range.
        self.assertGreaterEqual(len(set(energies)), 7)
        self.assertNotEqual(energies.count(50), len(energies))
        self.assertEqual(
            flow_energy(make_track("gospel-never", bpm=None, genre="Gospel",
                                  played_count=0, rating=0, favorited=False, skipped_count=0)),
            48,  # 50 base - 2 gospel nudge, no familiarity
        )
        self.assertEqual(
            flow_energy(make_track("unknown-never", bpm=None, genre="",
                                  played_count=0, rating=0, favorited=False, skipped_count=0)),
            50,  # the truly blank song still sits at mid-energy
        )
        self.assertEqual(
            flow_energy(make_track("ambient-never", bpm=None, genre="Ambient",
                                  played_count=0, rating=0, favorited=False, skipped_count=0)),
            38,  # 50 - 12, unchanged from the old ambient nudge
        )

    def test_new_genre_groups_map(self):
        self.assertEqual(genre_group("Gospel"), 8)
        self.assertEqual(genre_group("Christian"), 8)
        self.assertEqual(genre_group("Worship"), 8)
        self.assertEqual(genre_group("Praise & Worship"), 8)
        self.assertEqual(genre_group("Reggaeton"), 9)
        self.assertEqual(genre_group("Latin"), 9)
        # Substring order: "Latin Pop" hits the pop group first.
        self.assertEqual(genre_group("Latin Pop"), 3)
        self.assertEqual(genre_group("Afrobeats"), 10)
        self.assertEqual(genre_group("Soundtrack"), 11)

    def test_bpm_present_songs_score_exactly_as_before(self):
        # Old formula for a gospel BPM track: no genre nudge (group 7
        # under the legacy map), single >=20 plays step, rating, fav.
        self.assertEqual(
            flow_energy(make_track("g", bpm=120, genre="Gospel",
                                  played_count=5, rating=0, favorited=False)),
            75,
        )
        self.assertEqual(
            flow_energy(make_track("g2", bpm=120, genre="Gospel",
                                  played_count=30, rating=100, favorited=True)),
            90,  # 75 + 0 + 5 + 5 + 5, NOT tiered plays or a gospel nudge
        )
        # And the pre-existing BPM band tests still hold verbatim.
        self.assertEqual(flow_energy(make_track("a", bpm=70, genre="Rock", played_count=0)), 33)
        self.assertEqual(flow_energy(make_track("b", bpm=130, genre="Classical", played_count=0)), 63)

    def test_skip_penalty_applies_only_without_bpm_and_only_when_mostly_skipped(self):
        # 2 plays, 8 skips: fallback 50 + 8 rock + 2 tier - 5 penalty = 55.
        self.assertEqual(
            flow_energy(make_track("s", bpm=None, genre="Rock",
                                  played_count=2, rating=0, favorited=False, skipped_count=8)),
            55,
        )
        # Same song WITH bpm: old formula, no skip penalty at all.
        self.assertEqual(
            flow_energy(make_track("s2", bpm=120, genre="Rock",
                                  played_count=2, rating=0, favorited=False, skipped_count=8)),
            83,
        )
        # Skip-heavy song is still Flow-eligible (penalty, not exclusion).
        tracks = [make_track("ok", bpm=120), make_track("skippy", bpm=None, genre="Pop",
                                                        played_count=1, skipped_count=9)]
        ordered, _, eligible = prepare_flow(tracks, Settings(flow_size=2))
        self.assertEqual(eligible, 2)
        self.assertEqual(len(ordered), 2)

    def test_prepare_flow_missing_bpm_spread(self):
        tracks = [make_track(name, bpm=None, **kw) for name, kw in self.missing_bpm_cases()]
        ordered, energies, eligible = prepare_flow(tracks, Settings(flow_size=10))
        self.assertEqual(eligible, 10)
        self.assertGreaterEqual(len(set(energies)), 7)

    def test_familiarity_tie_break_is_deterministic_and_prefers_movement(self):
        # Position 2 cost tie: same-group song at distance 20 (cost 20)
        # vs different-group song at distance 0 (cost 0 + 20 genre = 20).
        # The movement tie-break must pick the different-group song,
        # even though it is later in the pool.
        order = flow_order(
            [50, 70, 90], [3, 3, 7], [None, None, None], ["", "", ""],
            3, spacing=2, familiarity=[0, 0, 0],
        )
        self.assertEqual(order, [0, 2, 1])
        # Familiarity breaks a tie before earliest-pool order does.
        order = flow_order(
            [50, 50, 50], [3, 3, 3], [None, None, None], ["", "", ""],
            3, spacing=2, familiarity=[0, 10, 0],
        )
        self.assertEqual(order[0], 1)
        # Same input twice gives the same order.
        self.assertEqual(
            flow_order([50, 70, 90], [3, 3, 7], [None, None, None], ["", "", ""], 3, spacing=2),
            flow_order([50, 70, 90], [3, 3, 7], [None, None, None], ["", "", ""], 3, spacing=2),
        )
        self.assertEqual(familiarity(make_track("f", played_count=30, rating=100, favorited=True)), 60)


class AuditTests(unittest.TestCase):
    def test_audit_counts_match_the_fixture(self):
        tracks = load_library(FIXTURE)
        report = audit_library(tracks)
        self.assertEqual(report["total"], 8)
        self.assertEqual(report["bpm_present"], 7)
        self.assertEqual(report["bpm_missing"], 1)
        self.assertEqual(report["bpm_zero"], 0)
        self.assertEqual(report["genre_present"], 8)
        self.assertEqual(report["genre_missing"], 0)
        self.assertEqual(report["genre_distinct"], 5)
        self.assertEqual(report["genre_counts"][0], ("Pop", 3))
        self.assertEqual(report["genre_counts"][1], ("Electronic", 2))
        self.assertEqual(report["played_bands"], {"0": 1, "1-4": 2, "5-19": 1, "20-49": 3, "50+": 1})
        self.assertEqual(report["rating_bands"]["unrated"], 5)
        self.assertEqual(report["rating_bands"]["4-5 stars"], 3)
        self.assertEqual(report["favorited"], 2)
        self.assertEqual(report["disliked"], 1)
        self.assertEqual(report["enabled"], 7)
        self.assertEqual(report["disabled"], 1)
        self.assertEqual(report["flow_eligible"], 6)
        self.assertEqual(report["flow_eligible_missing_bpm"], 1)

    def test_audit_separates_bpm_zero_from_missing(self):
        tracks = [
            make_track("present", bpm=120),
            make_track("missing", bpm=None),
            make_track("zero", bpm=0),
        ]
        report = audit_library(tracks)
        self.assertEqual((report["bpm_present"], report["bpm_missing"], report["bpm_zero"]), (1, 1, 1))

    def test_audit_format_lists_top_genres_and_changes_nothing(self):
        tracks = load_library(FIXTURE)
        before = [t.persistent_id for t in tracks]
        lines = format_audit(audit_library(tracks), top_genres=2)
        text = "\n".join(lines)
        self.assertIn("BPM: present 7 (87.5%)", text)
        self.assertIn("Pop", text)
        self.assertIn("Nothing was changed.", text)
        self.assertEqual([t.persistent_id for t in tracks], before)

    def test_cli_audit_reports_and_leaves_fixture_untouched(self):
        before = hashlib.sha256(FIXTURE.read_bytes()).hexdigest()
        result = subprocess.run(
            [sys.executable, "-m", "seter_shuffle.cli", "audit", "--library", str(FIXTURE)],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Audit: 8 songs.", result.stdout)
        self.assertIn("BPM: present 7", result.stdout)
        self.assertIn("Nothing was changed.", result.stdout)
        self.assertEqual(hashlib.sha256(FIXTURE.read_bytes()).hexdigest(), before)


if __name__ == "__main__":
    unittest.main()
