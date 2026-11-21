"""Flow relative arc (2026-10-29 experimental).

Spencer's 2026-10-29 audit: his library had BPM missing on 100% of
tracks and fallback energies spanning only 47..68, so the fixed
45..90..40 arc aims at a peak the pool cannot reach and a tail
below its floor. prepare_flow now rescales the arc into the pool's
own energy range, but only when every pool track is BPM-missing
and the range is at least 10. BPM pools keep the fixed arc exactly,
and narrow fallback pools keep it too, rather than amplifying noise.

No test here touches Music or the network. Standard library only.
"""

from __future__ import annotations

import random
import unittest
from datetime import datetime, timezone
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.flow import (
    _arc_target,
    flow_energy,
    flow_order,
    prepare_flow,
)
from seter_shuffle.settings import Settings
from seter_shuffle.tracks import Track

NOW = datetime(2026, 10, 29, tzinfo=timezone.utc)


def _track(pid, genre="Pop", bpm=None, plays=0, rating=0, year=2020):
    return Track(
        persistent_id=pid, name=pid, artist=f"Artist {pid}", genre=genre,
        bpm=bpm, year=year, played_count=plays, skipped_count=0,
        rating=rating, favorited=False,
    )


class RelativeArcTests(unittest.TestCase):
    def test_arc_target_scaling_math(self):
        # Fixed arc for total 5: 45, 67.5, 90, 65, 40. Rescaled into
        # [50, 70]: 52, 61, 70, 60, 50.
        self.assertEqual(
            [_arc_target(p, 5, 50, 70) for p in range(1, 6)],
            [52.0, 61.0, 70.0, 60.0, 50.0],
        )

    def test_arc_target_unchanged_without_bounds_or_narrow_range(self):
        from seter_shuffle.flow import flow_target_energy

        for lo, hi in ((None, None), (50, 55), (60, 50)):
            for position in range(1, 6):
                self.assertEqual(
                    _arc_target(position, 5, lo, hi),
                    flow_target_energy(position, 5),
                )

    def test_flow_order_rescaled_walk_differs_from_fixed_walk(self):
        energies = [40, 50, 60, 70, 80]
        groups = [1, 2, 3, 4, 5]
        years = [None] * 5
        keys = [f"A{i}" for i in range(5)]
        scaled = flow_order(energies, groups, years, keys, 5, 2,
                            familiarity=[0] * 5, arc_lo=50, arc_hi=70)
        fixed = flow_order(energies, groups, years, keys, 5, 2,
                           familiarity=[0] * 5)
        self.assertEqual([energies[i] for i in scaled], [50, 60, 80, 70, 40])
        # Position 4, rescaled target 60, falling: 40 and 80 tie on
        # distance (20 each) and on genre cost (both unrelated to
        # group 4, +8 each), so the old walk took the earlier song,
        # 40, and then ended the playlist on 80, the hottest song,
        # against a falling tail. The directional cost adds +5 to
        # 40 for sitting below a falling target, so the tie breaks
        # toward 80 instead, and the walk ends on 40, the coldest
        # song, which is what the tail wants. Total arc distance
        # drops from 53 to 33.
        # (2026-11-17 stranded-song rule: the 80 now lands at the
        # peak slot instead. At position 3, target 70, the 80 fits
        # now 10 off but fits no later target well (best later fit
        # 20 off, to the 60 target), so it is stranded and is picked
        # now, and the 70 takes the falling slot instead. Total arc
        # distance is unchanged at 33, but the peak lands where the
        # arc peaks instead of one slot late, and the sequence rises
        # then falls instead of rising past the peak.)
        # Fixed walk, position 2: 70 is closest to 67.5 (2.5) but its
        # group is unrelated to group 1 (+8, total 10.5), tying 60,
        # whose group is related (+3, total 10.5); the tie-break
        # takes the earlier song, 60, then 80 at the peak.
        self.assertEqual([energies[i] for i in fixed], [40, 60, 80, 70, 50])
        self.assertNotEqual(scaled, fixed)

    def test_prepare_flow_all_fallback_rises_and_falls_within_range(self):
        # Narrow fallback pool: energies roughly 50..70, built only
        # from genre + play tiers + rating, all BPM missing.
        tracks = []
        for i in range(40):
            tracks.append(_track(
                f"F{i}", genre="Pop" if i % 2 else "Hip-Hop",
                plays=(i * 3) % 70, rating=80 if i % 5 == 0 else 0,
                year=2020 + (i % 5)))
        ordered, energies, eligible = prepare_flow(
            tracks, Settings(flow_size=20, flow_pool_max=0),
            random.Random(7), now=NOW)
        self.assertEqual(eligible, 40)
        self.assertEqual(len(energies), 20)
        self.assertGreaterEqual(min(energies), 47)
        # Pool max on this synthetic profile is 77 (50 + 8 Pop
        # nudge + 12 top play tier + 5 rating + 2 era band).
        self.assertLessEqual(max(energies), 77)
        first_mean = sum(energies[:5]) / 5
        peak_mean = sum(energies[8:14]) / 6
        tail_mean = sum(energies[-5:]) / 5
        # A relative wave: the middle sits above both ends.
        self.assertGreater(peak_mean, first_mean + 3)
        self.assertGreater(peak_mean, tail_mean + 3)
        # The peak actually reaches near the pool top, which the
        # fixed arc cannot do on this range (it would aim at 90
        # and stop at the closest available song each step).
        self.assertGreaterEqual(max(energies), 68)

    def test_prepare_flow_bpm_pool_keeps_fixed_arc(self):
        tracks = [_track(f"B{i}", bpm=120 + i, plays=i) for i in range(20)]
        ordered, energies, eligible = prepare_flow(
            tracks, Settings(flow_size=10, flow_pool_max=0),
            random.Random(3), now=NOW)
        pool_energies = [flow_energy(t, now=NOW) for t in tracks]
        from seter_shuffle.artists import artist_key
        from seter_shuffle.flow import genre_group, familiarity

        groups = [genre_group(t.genre) for t in tracks]
        years = [t.year for t in tracks]
        keys = [artist_key(t.artist, True) for t in tracks]
        fams = [familiarity(t) for t in tracks]
        expected = flow_order(pool_energies, groups, years, keys, 10, 2,
                              familiarity=fams)
        self.assertEqual(
            [t.persistent_id for t in ordered],
            [tracks[i].persistent_id for i in expected])

    def test_prepare_flow_narrow_fallback_keeps_fixed_arc(self):
        # All fallback, but range under 10: no rescaling.
        tracks = [_track(f"N{i}", plays=0, rating=0) for i in range(10)]
        ordered, energies, eligible = prepare_flow(
            tracks, Settings(flow_size=10, flow_pool_max=0),
            random.Random(3), now=NOW)
        pool_energies = [flow_energy(t, now=NOW) for t in tracks]
        self.assertLess(max(pool_energies) - min(pool_energies), 10)
        from seter_shuffle.artists import artist_key
        from seter_shuffle.flow import genre_group, familiarity

        groups = [genre_group(t.genre) for t in tracks]
        years = [t.year for t in tracks]
        keys = [artist_key(t.artist, True) for t in tracks]
        fams = [familiarity(t) for t in tracks]
        expected = flow_order(pool_energies, groups, years, keys, 10, 2,
                              familiarity=fams)
        self.assertEqual(
            [t.persistent_id for t in ordered],
            [tracks[i].persistent_id for i in expected])


if __name__ == "__main__":
    unittest.main()
