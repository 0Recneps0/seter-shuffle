"""Artist keys: how "same artist" is judged for spacing.

Mirrors v2.6's artistKey handler, including its quirks, with one
deliberate difference (2026-11-03 experimental): the key is
lowercased. v2.6's AppleScript comparison is case-insensitive, but
the Python port compared keys with ==, so "Drake" and "drake" from
different rips counted as different artists and defeated spacing.
The key is used only for equality comparisons (shuffle/Flow
spacing, Rediscover max-per-artist), never displayed, so lowercasing
it changes no output text, only which tracks count as the same
artist. Other quirks kept:
- With featuring_is_same_artist, "Artist feat. X" / "Artist (ft. X)" count
  as "Artist", so a featured track cannot sneak in next to the main
  artist's songs.
- The first matching marker wins in the order listed below, because
  each truncation feeds the next search.
- A trailing space left by a marker is stripped; v2.6's markers mostly
  start with a space, so the two agree on real-world names.
- Leading and trailing whitespace is stripped (2026-11-11
  experimental): rips and taggers leave stray spaces, and the marker
  truncation only stripped the tail, so " Drake feat. X" kept its
  leading space and "Drake " was a different key from "Drake".
  Whitespace-only names map to "" like empty and None do.
- `artist_compare_key` (merged 2026-11-20 from Claude's v3.0.11
  candidate) is the stricter comparison key built on artist_key:
  NFKC normalisation plus casefold plus internal-whitespace
  collapse, so full-width letters and unicode case variants also
  compare equal, and an optional split_collabs cut ("A & B" counts
  as "A", off by default). Every comparison in the core goes
  through artist_compare_key, never raw artist_key.
"""

from __future__ import annotations

import unicodedata

# Ordered exactly as in v2.6's artistKey.
_FEATURING_MARKERS = (
    " feat.",
    " feat ",
    " ft.",
    " ft ",
    " featuring",
    " (feat",
    " (ft",
)


def artist_key(artist: str | None, featuring_is_same_artist: bool = True) -> str:
    """Return the comparable artist key for a raw artist string.

    Lowercased: the key exists only for == comparisons, and library
    metadata spells the same artist in different cases ("Drake" vs
    "drake"), so case must not split one artist into two. Leading
    and trailing whitespace is stripped for the same reason: rips
    and taggers leave stray spaces, and the featuring truncation
    only stripped the tail, so " Drake feat. X" kept its leading
    space and "Drake " was a different key from "Drake". Empty,
    whitespace-only, and None still map to "" (never a clash).
    """
    if artist is None:
        return ""
    name = str(artist).strip()
    if not name:
        return ""
    if not featuring_is_same_artist:
        return name.lower()
    lowered = name.lower()
    if " f" not in lowered and " (f" not in lowered:
        return lowered
    result = name
    for marker in _FEATURING_MARKERS:
        idx = result.lower().find(marker)
        if idx > 0:
            result = result[:idx]
    return result.rstrip().lower()


# Optional collaboration separators (off by default; see Settings.split_collabs).
_COLLAB_SEPARATORS = (" & ", ", ", " and ", " x ", " \u00d7 ", " with ", " vs. ", " vs ", " + ")


def _primary_artist(name: str) -> str:
    """Text before the earliest collaboration separator (case-insensitive)."""
    lowered = name.lower()
    cut = len(name)
    for sep in _COLLAB_SEPARATORS:
        idx = lowered.find(sep)
        if 0 < idx < cut:
            cut = idx
    return name[:cut].rstrip()


def artist_compare_key(
    artist: str | None,
    featuring_is_same_artist: bool = True,
    split_collabs: bool = False,
) -> str:
    """Key for COMPARING artists: artist_key, then NFKC + casefold + trimmed.

    artist_key already lowercases and strips (2026-11-03 and 2026-11-11
    experimental), so this adds what it cannot: NFKC normalisation
    (full-width letters compare equal to ASCII), casefold for unicode
    case variants lower() misses, and collapse of internal runs of
    whitespace. With split_collabs, "A & B", "A, B", "A x B" and
    similar compare as "A" (opt-in: it changes which songs count as
    neighbours). Every comparison in the core uses this function,
    never raw artist_key.
    """
    key = artist_key(artist, featuring_is_same_artist)
    if split_collabs and key:
        key = _primary_artist(key)
    return " ".join(unicodedata.normalize("NFKC", key).casefold().split())
