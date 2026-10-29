"""Tests for the 2026-10-29 Flow energy fix.

Spencer's real flowPreview came back flat: the first 25 energies were
almost all 47-50 for a gospel-heavy library, because most of those
tracks share the same signals (same genre group, low plays, unrated,
not favorited, BPM missing) and because the old walk's genre cost
(0/8/20) outweighed the whole energy distance, so the walk stayed in
one cluster and then jumped to another at the peak: a cliff, not a
wave. The synthetic library below mirrors that profile (200 low-play
gospel/Christian tracks plus 60 higher-play hip-hop/pop tracks, all
BPM missing) and proves the fixed walk actually arcs.

No test here touches Music or the network. Standard library only.
"""

from __future__ import annotations

import random
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.flow import flow_energy, prepare_flow
from seter_shuffle.settings import Settings
from seter_shuffle.tracks import Track

NOW = datetime(2026, 10, 29, tzinfo=timezone.utc)
ROOT = Path(__file__).resolve().parents[1]

GENRES = ["Gospel", "Christian", "Worship", "Contemporary Christian",
          "Choir", "Praise & Worship", "Gospel", "Christian"]
ARTISTS = ["Maverick City Music", "Sunday Service Choir", "Hulvey",
           "Pastor Mike Jr.", "Koryn Hawthorne", "KB", "Lecrae",
           "Jor'dan Armstrong", "DOE", "Forrest Frank"]


def gospel_heavy_library() -> list[Track]:
    tracks = []
    for i in range(200):
        tracks.append(Track(
            persistent_id=f"T{i:03d}", name=f"Song {i}",
            artist=ARTISTS[i % len(ARTISTS)], genre=GENRES[i % len(GENRES)],
            bpm=None, year=2015 + (i % 10), played_count=i % 5,
            skipped_count=i % 4, rating=0, favorited=False,
            played_date=datetime(2024 + (i % 3), 1, 1, tzinfo=timezone.utc),
            date_added=datetime(2020 + (i % 6), 1, 1, tzinfo=timezone.utc),
        ))
    for j in range(60):
        tracks.append(Track(
            persistent_id=f"H{j:03d}", name=f"Hot {j}",
            artist=f"Rapper {j}", genre="Hip-Hop" if j % 2 else "Pop",
            bpm=None, year=2020 + (j % 5), played_count=20 + (j % 40),
            skipped_count=0, rating=80 if j % 3 == 0 else 0,
            favorited=(j % 4 == 0),
            played_date=datetime(2025, 6, 1, tzinfo=timezone.utc),
            date_added=datetime(2023, 1, 1, tzinfo=timezone.utc),
        ))
    return tracks


def max_run(values: list[int]) -> int:
    best = run = 0
    prev = None
    for value in values:
        run = run + 1 if value == prev else 1
        prev = value
        best = max(best, run)
    return best


class GospelHeavyArcTests(unittest.TestCase):
    def test_gospel_heavy_flow_arcs_instead_of_clumping(self):
        ordered, energies, eligible = prepare_flow(
            gospel_heavy_library(), Settings(flow_size=50, flow_pool_max=0),
            random.Random(42), now=NOW)
        self.assertEqual(eligible, 260)
        self.assertEqual(len(energies), 50)
        first_25 = energies[:25]
        # No flat block: the old walk gave a 16-long run of exactly
        # 50 in the first 25 on this profile.
        self.assertLessEqual(max_run(first_25), 4)
        self.assertGreaterEqual(len(set(first_25)), 10)
        # A real rise, then a real fall: early mean well below the
        # peak band, and the tail well below the peak band.
        first_10_mean = sum(energies[:10]) / 10
        peak_mean = sum(energies[19:33]) / 14
        tail_mean = sum(energies[-5:]) / 5
        self.assertGreater(peak_mean, first_10_mean + 10)
        self.assertLess(tail_mean, peak_mean - 10)
        # The order itself is deterministic for a fixed seed.
        ordered_again, energies_again, _ = prepare_flow(
            gospel_heavy_library(), Settings(flow_size=50, flow_pool_max=0),
            random.Random(42), now=NOW)
        self.assertEqual(energies, energies_again)
        self.assertEqual(
            [t.persistent_id for t in ordered],
            [t.persistent_id for t in ordered_again])

    def test_gospel_subgroups_spread_inside_group_8(self):
        base = dict(bpm=None, played_count=0, rating=0, favorited=False,
                    skipped_count=0, year=2020)
        choir = flow_energy(Track(persistent_id="c", name="c", genre="Choir", **base))
        worship = flow_energy(Track(persistent_id="w", name="w", genre="Worship", **base))
        plain = flow_energy(Track(persistent_id="g", name="g", genre="Gospel", **base))
        contemp = flow_energy(Track(persistent_id="k", name="k",
                                    genre="Contemporary Christian", **base))
        self.assertLess(choir, worship)
        self.assertLess(worship, plain)
        self.assertLess(plain, contemp)
        self.assertEqual((choir, worship, plain, contemp), (46, 48, 50, 53))

    def test_finer_play_tiers_are_monotonic(self):
        energies = [
            flow_energy(Track(persistent_id=f"p{plays}", name="x", genre="Pop",
                              bpm=None, played_count=plays, rating=0,
                              favorited=False, skipped_count=0, year=2020))
            for plays in (0, 1, 4, 15, 40, 80)
        ]
        self.assertEqual(energies, sorted(energies))
        self.assertGreater(len(set(energies)), 4)

    def test_recency_uses_only_the_supplied_clock(self):
        base = dict(bpm=None, played_count=20, rating=0, favorited=False,
                    skipped_count=0, year=2020,
                    date_added=datetime(2020, 1, 1, tzinfo=timezone.utc))
        recent = flow_energy(Track(persistent_id="r", name="r", genre="Pop",
                                   played_date=NOW - timedelta(days=10), **base),
                             now=NOW)
        stale = flow_energy(Track(persistent_id="s", name="s", genre="Pop",
                                  played_date=NOW - timedelta(days=1000), **base),
                            now=NOW)
        self.assertEqual(recent - stale, 5)  # +3 recent vs -2 stale
        # Without a clock, recency contributes nothing: deterministic.
        self.assertEqual(
            flow_energy(Track(persistent_id="n", name="n", genre="Pop",
                              played_date=NOW - timedelta(days=10), **base)),
            flow_energy(Track(persistent_id="o", name="o", genre="Pop",
                              played_date=NOW - timedelta(days=1000), **base)))

    def test_bpm_present_scores_ignore_all_new_signals(self):
        # Old formula only: 120-139 band 75 + rock 8 = 83, even with
        # heavy skips, an old year, and a stale played date.
        track = Track(persistent_id="b", name="b", genre="Rock", bpm=120,
                      played_count=2, skipped_count=8, rating=0,
                      favorited=False, year=1980,
                      played_date=datetime(2010, 1, 1, tzinfo=timezone.utc),
                      date_added=datetime(2010, 1, 1, tzinfo=timezone.utc))
        self.assertEqual(flow_energy(track, now=NOW), 83)


class NoNetworkInFlowPathTests(unittest.TestCase):
    def test_flow_path_has_no_network_imports_or_calls(self):
        banned = ("urllib", "requests", "socket", "urlopen", "http.client",
                  "urlrequest", "aiohttp", "httpx")
        for name in ("flow.py", "tracks.py", "settings.py", "artists.py",
                     "cli.py", "shuffle.py", "rediscover.py"):
            text = (ROOT / "seter_shuffle" / name).read_text(encoding="utf-8")
            for token in banned:
                self.assertNotIn(token, text, f"{name} contains {token}")
            self.assertNotIn("api_key", text.lower(), f"{name} mentions api_key")


if __name__ == "__main__":
    unittest.main()
