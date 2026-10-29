"""Daily library-manifest writer (v2.6 parity, Python form).

Stable v2.6's daily run saved a once-a-day library manifest
(ID, artist, album, title) under ~/Documents/SeTeRShuffle/backups/,
kept 14 days. The Python core previously had no equivalent: its
dumps lived in a per-run temporary directory and were deleted on
exit. This module closes that gap in the simplest honest form:
given already-loaded Track objects, write a tab-separated manifest
with exactly the v2.6 columns, one row per track, in dump order.
It never touches Music, never reads a playlist, and never invents
a track. Pruning of old manifests is the caller's job (daily.sh
does it, keeping 14 days, matching v2.6's backupKeepDays).
"""

from __future__ import annotations

from pathlib import Path

from .tracks import Track

HEADER = ("persistent_id", "artist", "album", "title")


def _clean(value: str) -> str:
    """Make one field safe for a tab-separated line."""
    return value.replace("\t", " ").replace("\n", " ").replace("\r", " ")


def manifest_lines(tracks: list[Track]) -> list[str]:
    # Header order is persistent_id, artist, album, title, and each
    # row matches it exactly (id, artist, album, title).
    rows = ["\t".join(HEADER)]
    for track in tracks:
        rows.append(
            "\t".join(
                (
                    _clean(track.persistent_id),
                    _clean(track.artist),
                    _clean(track.album),
                    _clean(track.name),
                )
            )
        )
    return rows


def write_library_manifest(tracks: list[Track], out_path: str | Path) -> int:
    """Write the manifest and return the number of tracks written."""
    path = Path(out_path)
    if path.parent and str(path.parent):
        path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(manifest_lines(tracks)) + "\n", encoding="utf-8")
    return len(tracks)
