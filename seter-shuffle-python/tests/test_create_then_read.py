"""Tests for the .4 create-then-read fix (failure mode 34).

Background: on 2026-10-29 Spencer ran ./run.sh flow "SeTeR Flow"
from the .3 folder. Flow compute and validation passed, but
apply-order failed at the first bulk ID read with AppleScript
error -1728 ("Can't get persistent ID of every track of user
playlist id 78940 ... whose media kind = song"). Spencer then
confirmed the target playlist did not exist yet in Music, so the
failing path is: resolvePlaylist(allowCreate=true) creates the
playlist via `make new user playlist`, and a subsequent bulk
filtered read on that freshly created (empty) playlist fails.
Safety worked (no snapshot written, playlist untouched), but a
flow into a missing playlist could never succeed.

The fix, in bridge/apply-order.applescript (the build path) and,
for consistency, in the retired standalone probe-order script's
playlistIDs fallback. The audit found one other creator:
probe-order.applescript creates its own 3-song throwaway, but it
is retired from builds (run.sh probe only, never a build target)
and deletes its playlist afterwards; undo, restore-original, and
sort-probe all resolve existing playlists and refuse when missing,
so no build path besides apply-order creates:
  1. After creating a playlist, re-resolve it by id with a fresh
     lookup instead of building from the make-new return value,
     which can go stale when Music / iCloud sync re-identifies
     the new playlist.
  2. playlistIDs() falls back on a bulk-read error to an
     unfiltered track count: count 0 proves the snapshot is
     empty and returns {}, anything else rethrows, because a
     snapshot must never be guessed for a non-empty playlist.
  3. deletePlaylistSongs() applies the same fallback to its
     empty re-read: a filtered-count error plus an unfiltered
     count of 0 counts as verified empty, so a fresh empty
     playlist does not fail the delete-empty gate it already
     satisfies. A filtered error with tracks present still
     fails, since song vs non-song entries cannot be told apart.

These tests are structural because this machine has no Music app
or osascript: they assert the exact properties above hold in the
AppleScript text, and that no duplication can precede snapshot
verification in the run handler's order of operations.
"""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "bridge"
APPLY = (BRIDGE / "apply-order.applescript").read_text()


def _handler_lines(text: str, handler_start: str) -> list[str]:
    """Return lines of an AppleScript handler starting at handler_start.

    Handlers end at the next line that is exactly "end <name>" for a
    following handler or at end of file; here we cut at the next
    line starting with "on " or "end run" after the start, which is
    enough for the handlers under test (they contain no nested
    handler definitions).
    """
    lines = text.splitlines()
    start = next(i for i, line in enumerate(lines) if handler_start in line)
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("on ") or lines[i] == "end run":
            end = i
            break
    return lines[start:end]


class TestCreateThenRead(unittest.TestCase):
    def test_only_apply_order_creates_playlists(self):
        """Audit: no build-path script besides apply-order creates.

        probe-order is the one exception, and it is retired from
        builds: it creates only its own throwaway, reads it, and
        deletes it. Its playlistIDs carries the same empty
        fallback as apply-order for consistency.
        """
        creators = {
            script.name
            for script in sorted(BRIDGE.glob("*.applescript"))
            if "make new user playlist" in script.read_text()
        }
        self.assertEqual(
            creators, {"apply-order.applescript", "probe-order.applescript"}
        )
        probe = (BRIDGE / "probe-order.applescript").read_text()
        self.assertIn("count of tracks of pl) is 0 then return {}", probe)

    def test_create_branch_re_resolves_by_id(self):
        """The make-new return value is never used blindly."""
        resolve = _handler_lines(APPLY, "on resolvePlaylist(playlistName, allowCreate)")
        joined = "\n".join(resolve)
        self.assertIn("make new user playlist", joined)
        self.assertIn("set newID to id of newPl", joined)
        # The fresh lookup must come after the make-new, and must be
        # the value returned from the create branch.
        self.assertLess(
            joined.index("make new user playlist"),
            joined.index("first user playlist whose id is newID"),
        )
        self.assertIn("return first user playlist whose id is newID", joined)

    def test_playlist_ids_empty_fallback(self):
        """Bulk-read failure + unfiltered count 0 returns {}; else error."""
        handler = _handler_lines(APPLY, "on playlistIDs(pl)")
        joined = "\n".join(handler)
        self.assertIn("persistent ID of every track of pl whose media kind is song", joined)
        self.assertIn("playlistTrackCount(pl)", joined)
        self.assertIn("if my playlistTrackCount(pl) is 0 then return {}", joined)
        self.assertIn("could not read the playlist's song IDs", joined)
        # The fallback must not return the order or a guessed list.
        self.assertNotIn("return orderIDs", joined)

    def test_playlist_track_count_handler(self):
        """Unfiltered count helper exists and fails closed with -1."""
        handler = _handler_lines(APPLY, "on playlistTrackCount(pl)")
        joined = "\n".join(handler)
        self.assertIn("count of tracks of pl", joined)
        self.assertIn("return -1", joined)

    def test_delete_empty_uses_count_fallback(self):
        """deletePlaylistSongs treats filtered-error + count 0 as empty."""
        handler = _handler_lines(APPLY, "on deletePlaylistSongs(pl)")
        joined = "\n".join(handler)
        self.assertIn("count of (every track of pl whose media kind is song)", joined)
        self.assertIn("set remaining to my playlistTrackCount(pl)", joined)
        self.assertIn("if remaining is 0 then return true", joined)

    def test_snapshot_precedes_any_build(self):
        """In run: resolve, then snapshot, then build; never reversed."""
        run = APPLY.split("end run")[0]
        resolve_at = run.index('set destPl to my resolvePlaylist(playlistName, true)')
        snapshot_at = run.index("set backupIDs to my playlistIDs(destPl)")
        build_at = run.index("set buildResult to my buildAndVerifyMapping")
        self.assertLess(resolve_at, snapshot_at)
        self.assertLess(snapshot_at, build_at)

    def test_no_duplicate_before_delete_empty_gate(self):
        """rebuildList still refuses to duplicate into a non-empty list."""
        handler = _handler_lines(APPLY, "on rebuildList(pl, idList)")
        joined = "\n".join(handler)
        self.assertIn('if not emptied then return {"delete-not-empty"}', joined)
        self.assertLess(
            joined.index('if not emptied then return {"delete-not-empty"}'),
            joined.index("duplicate sourceTrack to pl"),
        )


if __name__ == "__main__":
    unittest.main()
