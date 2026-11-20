"""v3.0.11 fixes: case-insensitive artists, collabs, clock frame, Rediscover fill."""

from __future__ import annotations

import random
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.artists import artist_compare_key, artist_key
from seter_shuffle.rediscover import pick_rediscover
from seter_shuffle.settings import Settings
from seter_shuffle.shuffle import shuffle_tracks
from seter_shuffle.tracks import Track, dump_now


def tr(pid: str, artist: str = "Artist", **kw) -> Track:
    base = dict(persistent_id=pid, name=pid, artist=artist, genre="Pop", year=2020)
    base.update(kw)
    return Track(**base)


class ArtistCompareKeyTests(unittest.TestCase):
    def test_case_and_unicode_insensitive(self):
        self.assertEqual(artist_compare_key("ABBA"), artist_compare_key("Abba"))
        self.assertEqual(artist_compare_key("  Beyonc\u00e9 "), artist_compare_key("BEYONC\u00c9"))
        # NFKC: full-width letters compare equal to ASCII
        self.assertEqual(artist_compare_key("\uff21BBA"), artist_compare_key("abba"))

    def test_artist_key_is_normalized_in_this_line(self):
        # Merged 2026-11-20: the experimental line normalizes inside
        # artist_key itself (2026-11-03 case, 2026-11-11 whitespace),
        # so artist_key("ABBA") is "abba" here, not "ABBA" as in
        # Claude's v3.0.10-based tree (where test_core still pinned
        # the raw key). The NFKC layer lives in artist_compare_key.
        self.assertEqual(artist_key("ABBA"), "abba")

    def test_featuring_still_collapses(self):
        self.assertEqual(
            artist_compare_key("Vector feat. Luna"), artist_compare_key("VECTOR")
        )

    def test_collabs_off_by_default(self):
        self.assertNotEqual(artist_compare_key("Drake & Future"), artist_compare_key("Drake"))

    def test_collabs_opt_in(self):
        for name in ("Drake & Future", "Drake, Future", "Drake x Future", "Drake with Future"):
            self.assertEqual(
                artist_compare_key(name, split_collabs=True), "drake", name
            )
        # a name that merely contains the letters is untouched
        self.assertEqual(artist_compare_key("Brand New", split_collabs=True), "brand new")

    def test_empty_never_clashes_key(self):
        self.assertEqual(artist_compare_key(None), "")
        self.assertEqual(artist_compare_key("   "), "")


class ShuffleCaseTests(unittest.TestCase):
    def test_spacing_treats_abba_and_ABBA_as_one_artist(self):
        tracks = [tr(f"a{i}", "ABBA" if i % 2 else "Abba") for i in range(4)]
        tracks += [tr(f"b{i}", f"Other {i}") for i in range(12)]
        for seed in range(20):
            out = shuffle_tracks(tracks, spacing=2, rng=random.Random(seed))
            idx = [i for i, t in enumerate(out) if t.artist.lower() == "abba"]
            for a, b in zip(idx, idx[1:]):
                self.assertGreater(b - a, 2, f"seed {seed}: {idx}")


class DumpNowTests(unittest.TestCase):
    def test_dump_now_is_local_wall_clock_labelled_utc(self):
        now = dump_now()
        self.assertIs(now.tzinfo, timezone.utc)
        local = datetime.now()
        self.assertLess(abs((now.replace(tzinfo=None) - local).total_seconds()), 5)


class RediscoverFillTests(unittest.TestCase):
    def test_last_resort_fill_reaches_target_with_unique_songs(self):
        # per-artist cap 1 with only 2 artists: the capped passes run dry,
        # so the final (now weight-ordered) fill must still reach the target
        # without repeating a song.
        now = datetime(2026, 10, 28, tzinfo=timezone.utc)
        old = datetime(2015, 1, 1, tzinfo=timezone.utc)
        tracks = []
        for g in range(2):
            for k in range(6):
                # earlier library position = LOWER play count = lighter weight
                tracks.append(
                    tr(f"g{g}-{k}", f"Artist {g}", played_count=k + 1,
                       played_date=old, date_added=old, rating=0)
                )
        s = Settings(rediscover_min=8, rediscover_max=8, rediscover_max_per_artist=1)
        picked, _cands, target = pick_rediscover(tracks, now, s, set(), random.Random(3))
        self.assertEqual(len(picked), target)
        self.assertEqual(len({t.persistent_id for t in picked}), len(picked))


if __name__ == "__main__":
    unittest.main()
