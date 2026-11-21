"""Tests for the 2026-11-17 Flow stranded-song rule.

The greedy walk is short-sighted about the tail: on the fall it can
spend a slot on a cold song that fits a later target perfectly,
leaving a hot song with no target left to land on, so the playlist
ends on that hot song after the cold tail. A 7-song pool
[40, 44, 56, 69, 72, 87, 91] used to come back
[44, 56, 72, 91, 69, 40, 87]: the 87 ends the playlist, hotter than
everything except the 91 at the peak. The walk now checks, at each
slot, whether an unused song fits this slot clearly better than any
later slot and fits no later slot well; such a stranded song is
picked now, so the fall keeps falling instead of stranding a hot
song at the end.

The rule is deliberately narrow: it only fires when a song's best
later fit is bad (>= 20 off) and clearly worse than its fit now
(>= 10 worse), so dense pools are untouched, and artist spacing
(1000) still beats it. The tests below pin the rule at flow_order
level, where the arc targets are known exactly, plus one end-to-end
prepare_flow check.

No test here touches Music or the network. Standard library only.
"""

from __future__ import annotations

import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.flow import flow_order, flow_target_energy, prepare_flow
from seter_shuffle.settings import Settings
from seter_shuffle.tracks import Track

GROUP = 7
YEARS = [None, None, None, None, None, None, None, None, None, None]


def order_for(energies, artists=None, spacing=3, arc=None):
    n = len(energies)
    kwargs = {}
    if arc is not None:
        kwargs = {"arc_lo": arc[0], "arc_hi": arc[1]}
    return flow_order(
        list(energies),
        [GROUP] * n,
        YEARS[:n],
        list(artists) if artists is not None else [""] * n,
        n,
        spacing,
        **kwargs,
    )


def energies_of(order, energies):
    return [energies[i] for i in order]


def arc_error(order, energies):
    total = len(order)
    return sum(
        abs(energies[i] - flow_target_energy(position + 1, total))
        for position, i in enumerate(order)
    )


class StrandedSongTests(unittest.TestCase):
    def test_hot_song_joins_the_fall_instead_of_ending_it(self):
        # The pinned case: the old walk ended this playlist on 87,
        # hotter than everything except the 91 at the peak.
        energies = [40, 44, 56, 69, 72, 87, 91]
        order = order_for(energies)
        self.assertEqual(energies_of(order, energies),
                         [44, 56, 72, 91, 87, 69, 40])
        # It now ends on the coldest song, and the total arc error
        # is lower than the old order's.
        old_order = [1, 2, 4, 6, 3, 0, 5]
        self.assertEqual(energies_of(old_order, energies),
                         [44, 56, 72, 91, 69, 40, 87])
        self.assertLess(arc_error(order, energies),
                        arc_error(old_order, energies))

    def test_minimal_fall_case(self):
        # 5 songs, targets 45/67.5/90/65/40. The old walk spent the
        # 65 slot on the 55 and stranded the 85 at the end.
        energies = [40, 55, 70, 85, 95]
        order = order_for(energies)
        self.assertEqual(energies_of(order, energies),
                         [40, 70, 95, 85, 55])

    def test_dense_pool_lower_error_colder_end(self):
        # A dense pool: the rule fires on the tail, the total arc
        # error drops from 60 to 55, and the ending is colder.
        energies = [45, 50, 55, 60, 65, 70, 75, 80, 85, 90]
        order = order_for(energies)
        self.assertEqual(energies_of(order, energies),
                         [45, 50, 60, 70, 80, 90, 85, 75, 65, 55])
        old_energies = [45, 50, 60, 70, 80, 90, 75, 65, 55, 85]
        old_indices = [energies.index(e) for e in old_energies]
        self.assertLess(arc_error(order, energies),
                        arc_error(old_indices, energies))
        self.assertEqual(arc_error(order, energies), 55.0)
        self.assertEqual(arc_error(old_indices, energies), 60.0)

    def test_artist_spacing_still_beats_stranding(self):
        # The stranded 85 shares its artist with the 95 picked at the
        # peak, so spacing (1000) still wins over stranding (500):
        # the walk takes the 55 and leaves the 85 stranded, exactly
        # as the old walk did.
        energies = [40, 55, 70, 85, 95]
        order = order_for(energies, artists=["x", "b", "y", "a", "a"])
        self.assertEqual(energies_of(order, energies),
                         [40, 70, 95, 55, 85])

    def test_relative_arc_stranding(self):
        # The rule uses the rescaled targets, not the fixed arc: the
        # 90 is stranded under the 47..95 relative arc too.
        energies = [47, 60, 75, 90, 95]
        order = order_for(energies, arc=(47, 95))
        self.assertEqual(energies_of(order, energies),
                         [47, 75, 95, 90, 60])

    def test_dense_relative_pool_unchanged(self):
        # A dense rescaled pool: every song fits some later target
        # well, so the rule never fires and the order is untouched.
        energies = [47, 52, 58, 68, 85]
        order = order_for(energies, arc=(47, 85))
        self.assertEqual(energies_of(order, energies),
                         [47, 68, 85, 58, 52])

    def test_all_hot_pool_unchanged(self):
        # No cold tail exists at all: the rule cannot invent one, so
        # the order is exactly the old walk's.
        energies = [57, 59, 92, 94, 97]
        order = order_for(energies)
        self.assertEqual(energies_of(order, energies),
                         [57, 59, 92, 94, 97])

    def test_last_slot_has_no_later_targets(self):
        # With no slots left after the current one there is nothing
        # to strand against, so the rule is inert.
        self.assertEqual(order_for([40, 90]), [0, 1])
        self.assertEqual(order_for([55]), [0])


class StrandedSongEndToEndTests(unittest.TestCase):
    def test_prepare_flow_ends_on_the_cold_tail(self):
        # BPM energies 35/55/70/85/95: the 35 comes from a 90 BPM
        # track with a jazz -5 nudge, the 70 from a 130 BPM track
        # with the same nudge, the rest from plain BPM bands. The
        # old prepare_flow ended this list on the 85; the new one
        # ends on the 55.
        tracks = [
            Track("t35", "a", "Artist A", "jazz", bpm=90),
            Track("t55", "b", "Artist B", "", bpm=110),
            Track("t70", "c", "Artist C", "jazz", bpm=130),
            Track("t85", "d", "Artist D", "", bpm=150),
            Track("t95", "e", "Artist E", "", bpm=170),
        ]
        settings = Settings(flow_size=5, flow_pool_max=400, artist_spacing=2)
        ordered, ordered_energies, eligible = prepare_flow(tracks, settings)
        self.assertEqual(eligible, 5)
        self.assertEqual(ordered_energies, [35, 70, 95, 85, 55])
        self.assertEqual([t.persistent_id for t in ordered],
                         ["t35", "t70", "t95", "t85", "t55"])


if __name__ == "__main__":
    unittest.main()
