"""Tests for the 2026-11-05 Flow directional cost.

The greedy walk's distance term is symmetric: a song 5 above the arc
target costs the same as a song 5 below it. On a near-tie the walk
could therefore jump ahead of the arc on the rise (hotter than the
target) or drop below it on the fall (colder than the target), so
the actual energy sequence zigzagged around the arc instead of
tracking it. Each step now adds a small +5 when the candidate sits
on the wrong side of the target for the arc's direction at that
position. The tests below pin that rule at flow_order level, where
the arc targets are known exactly (total=3: 45/90/40, total=4:
45/90/65/40), plus one end-to-end prepare_flow check.

No test here touches Music or the network. Standard library only.
"""

from __future__ import annotations

import random
import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.flow import (
    _arc_direction,
    flow_energy,
    flow_order,
    prepare_flow,
)
from seter_shuffle.settings import Settings
from seter_shuffle.tracks import Track

GROUP = [3, 3, 3, 3]
YEARS = [2020, 2020, 2020, 2020]


def order_for(energies, artists, total, spacing=2):
    return flow_order(
        list(energies),
        GROUP[: len(energies)],
        YEARS[: len(energies)],
        list(artists),
        total,
        spacing,
    )


class DirectionHelperTests(unittest.TestCase):
    def test_direction_follows_the_arc(self):
        # total=3: 45 rising to 90, then 90 falling to 40. The peak
        # slot counts as falling, since the target after it is lower.
        self.assertEqual(_arc_direction(1, 3, None, None), 1)
        self.assertEqual(_arc_direction(2, 3, None, None), -1)
        self.assertEqual(_arc_direction(3, 3, None, None), -1)

    def test_direction_at_the_last_slot_is_arrival_direction(self):
        # A 2-song Flow ends at the peak (documented quirk), so the
        # last slot is still rising into it, not falling out of it.
        self.assertEqual(_arc_direction(1, 2, None, None), 1)
        self.assertEqual(_arc_direction(2, 2, None, None), 1)
        # A single-song Flow has no direction at all.
        self.assertEqual(_arc_direction(1, 1, None, None), 0)

    def test_direction_uses_the_rescaled_arc(self):
        # Relative arc 47..68: targets 49.1 / 68 / 47, same pattern.
        self.assertEqual(_arc_direction(1, 3, 47, 68), 1)
        self.assertEqual(_arc_direction(2, 3, 47, 68), -1)
        self.assertEqual(_arc_direction(3, 3, 47, 68), -1)


class DirectionalCostTests(unittest.TestCase):
    def test_rise_prefers_below_target_on_a_near_tie(self):
        # Position 1, target 45, rising. Both candidates cost 3 on
        # distance alone; the hotter one (48, listed first, so the
        # old tie-break would have taken it) now costs 3 + 5.
        self.assertEqual(order_for([48, 42], ["a", "b"], 3), [1, 0])

    def test_fall_prefers_above_target_on_a_near_tie(self):
        # Position 3, target 65, falling. 62 is closer on distance
        # (3 vs 5) but sits below the target, so it costs 3 + 5
        # against 70's 5. The walk stays warm instead of dropping
        # early. Full order, verified step by step against the
        # 45/90/65/40 targets: 45, then 90, then 70, then 62.
        self.assertEqual(
            order_for([45, 90, 62, 70], ["a", "b", "c", "d"], 4),
            [0, 1, 3, 2],
        )

    def test_peak_prefers_not_undershooting(self):
        # Position 2, target 90, the peak slot counts as falling.
        # 88 and 92 tie on distance (2 each); 88 costs 2 + 5 for
        # sitting below the peak, so the hotter song peaks instead.
        self.assertEqual(
            order_for([45, 88, 92], ["a", "b", "c"], 3), [0, 2, 1]
        )

    def test_closer_match_still_wins_over_the_penalty(self):
        # +5 only breaks near-ties. 46 is on the wrong side of the
        # rising 45 target but 15 closer than 30, so 6 beats 15
        # even with the penalty added.
        self.assertEqual(order_for([46, 30], ["a", "b"], 3), [0, 1])

    def test_flat_pool_order_is_unchanged(self):
        # Equal energies are penalised equally at every step (all
        # above the target on the rise, all below it at the peak),
        # so the ranking, and the order, do not change.
        self.assertEqual(
            order_for([50, 50, 50], ["a", "b", "c"], 3), [0, 1, 2]
        )

    def test_artist_spacing_still_beats_the_penalty(self):
        # 48 and 42 share artist "a"; 50 is artist "b". At the
        # peak target 90, 48 is far closer than 50, but it repeats
        # an artist picked one slot ago, so the 1000 spacing cost
        # keeps it out and the walk takes 50 instead.
        self.assertEqual(
            order_for([48, 42, 50], ["a", "a", "b"], 3), [1, 2, 0]
        )


class DirectionalCostEndToEndTests(unittest.TestCase):
    def test_prepare_flow_opens_below_the_arc_start(self):
        # Two BPM-missing tracks, both with no year (so no era band)
        # and no dates (so no recency): Country, unplayed -> 47;
        # Classical, 5 plays -> 41. The range is 6, under the
        # relative-arc threshold of 10, so the fixed 45/90 arc is
        # used. At the 45 target on the rise, 47 is closer on
        # distance alone (2 vs 4), so the old walk opened on it;
        # now 47 costs 2 + 5 for sitting above a rising target, so
        # the walk opens on 41 and climbs 41 -> 47, starting cool
        # instead of starting warm.
        country = Track(
            persistent_id="c", name="c", artist="a1", genre="Country",
            bpm=None, year=None, played_count=0, skipped_count=0,
            rating=0, favorited=False)
        classical = Track(
            persistent_id="k", name="k", artist="a2", genre="Classical",
            bpm=None, year=None, played_count=5, skipped_count=0,
            rating=0, favorited=False)
        self.assertEqual(flow_energy(country), 47)
        self.assertEqual(flow_energy(classical), 41)
        ordered, energies, eligible = prepare_flow(
            [country, classical],
            Settings(flow_size=2, flow_pool_max=0), random.Random(7))
        self.assertEqual(eligible, 2)
        self.assertEqual(energies, [41, 47])
        self.assertEqual(
            [t.genre for t in ordered], ["Classical", "Country"])


if __name__ == "__main__":
    unittest.main()
