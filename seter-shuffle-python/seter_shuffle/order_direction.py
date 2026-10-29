"""Playlist order direction: the pure-Python mirror of the bridge's mode logic.

Background: on 2026-10-28 the .4 bridge failed on a real 806-song
playlist in a loop. Apply, its restore, and undo all failed exact-order
verification, and the pre-undo snapshot pulled off the Mac turned out
to be the EXACT REVERSE of the original backup (806/806 same songs).
Two mechanisms explain that evidence equally well, and the backup files
alone cannot distinguish them:

  (a) insert-reversed: `duplicate track to playlist` inserts at the
      TOP of the playlist on that Music version, so duplicating in
      order lands reversed, while the every-track read is faithful.
  (b) read-reversed: duplicating appends normally, but `persistent ID
      of every track of playlist` returns tracks in reverse playlist
      order, so the read is reversed while the display is correct.

The bridge therefore never guesses. A probe (bridge/probe-order.applescript)
measures the direction on the actual Mac before any real build, and
run.sh passes one of three modes to apply/undo:

  "forward":        duplicate in order; the list read equals the order.
  "insert-reversed": duplicate in REVERSE order; the list read then
                    equals the order (the insertion flips it back).
  "read-reversed":   duplicate in order; the list read equals the
                    REVERSE of the order (the read flips it).

There are two kinds of build, and they differ in what "the order" is:

  * An APPLY build wants a DISPLAY order O (the order file, as printed
    by the Python core). build_for_apply / expected_for_apply give the
    duplicate order and the list-read expectation for that display
    order, per mode.
  * A RESTORE build wants to get back to a LIST-READ snapshot T (a
    backup file, which is always a list-read snapshot, never a display
    order). Under "forward", T is already the display order. Under
    either reversed mode, the display order behind T is reverse(T),
    and duplicating reverse(T) lands the display back on it: under
    insert-reversed the insertion flips reverse(T) to T, and under
    read-reversed the append lands reverse(T) as the display. In all
    three modes the list read afterwards equals T, so
    expected_for_restore is T in every mode, and build_for_restore is
    T under "forward" and reverse(T) otherwise.

This module is the testable copy of that logic. The AppleScript
handlers in apply-order.applescript, undo.applescript, and
restore-original.applescript must match it exactly; if they ever
drift, the bridge is wrong even though these tests pass, because the
tests run here and the bridge runs on a Mac. The handlers are named
the same as these functions (buildForApply, expectedForApply,
buildForRestore, expectedForRestore) so a drift can be spotted by
reading the two side by side.
"""

from __future__ import annotations

from typing import Sequence, TypeVar

MODES = ("forward", "insert-reversed", "read-reversed")

T = TypeVar("T")


def parse_mode(value: str) -> str:
    """Validate a probe mode string; raise ValueError on anything else."""
    if value not in MODES:
        raise ValueError(
            f"unknown playlist order mode: {value!r} "
            f"(expected one of: {', '.join(MODES)})"
        )
    return value


def reverse_list(items: Sequence[T]) -> list[T]:
    """Return a reversed copy; the input is never mutated."""
    return list(items)[::-1]


def build_for_apply(order: Sequence[T], mode: str) -> list[T]:
    """Duplicate order for an apply build wanting display order `order`."""
    parse_mode(mode)
    if mode == "insert-reversed":
        return reverse_list(order)
    return list(order)


def expected_for_apply(order: Sequence[T], mode: str) -> list[T]:
    """List-read expectation after an apply build of display order `order`."""
    parse_mode(mode)
    if mode == "read-reversed":
        return reverse_list(order)
    return list(order)


def build_for_restore(snapshot: Sequence[T], mode: str) -> list[T]:
    """Duplicate order for a restore build from list-read snapshot `snapshot`."""
    parse_mode(mode)
    if mode == "forward":
        return list(snapshot)
    return reverse_list(snapshot)


def expected_for_restore(snapshot: Sequence[T], mode: str) -> list[T]:
    """List-read expectation after a restore build from `snapshot`.

    Always the snapshot itself, in every mode: that is what makes a
    restore verifiable without knowing which reversed mechanism is in
    play, as long as the build order above is used.
    """
    parse_mode(mode)
    return list(snapshot)


def display_order_for_snapshot(snapshot: Sequence[T], mode: str) -> list[T]:
    """Display order that a list-read snapshot `snapshot` represents.

    Under "read-reversed" the snapshot is the reverse of the display
    order; under the other modes it is the display order itself. This
    is only needed when a caller must reason about display order
    directly (for example, a diagnostic message); the build/expected
    functions above already encode it, so prefer them.
    """
    parse_mode(mode)
    if mode == "read-reversed":
        return reverse_list(snapshot)
    return list(snapshot)




# ---------------------------------------------------------------------------
# SORT-MATCHED BUILD MAPPING (2026-10-29, supersedes both the probe modes
# above and the list-vs-index sort classification that was drafted and
# then discarded in the same session)
#
# Why the earlier models are dead, in one paragraph each:
#
#   * Fresh-probe modes (above, LEGACY): a fresh 3-song playlist
#     reported "forward" on 2026-10-28 while the real 806-song
#     playlist still failed every build. A fresh playlist does not
#     share the real playlist's sort, so its direction says nothing
#     about the target.
#   * List-vs-index sort classification (drafted 2026-10-29, then
#     DISCARDED before publication): it assumed the track `index`
#     property is the manual playlist position, so comparing the
#     every-track list read against the index order would reveal a
#     descending sort. The read-only diagnostic on the real playlist
#     killed that assumption: the current list read is the exact
#     reverse of the original backup (first 54BC5E32EB0D0F8E, last
#     B49A108A0E5553DB, positional reads agreeing exactly), yet the
#     list's first track has index 1. If index were manual order
#     and the list were sorted descending (reverse of manual), that
#     track would carry index 806, not 1. So either index simply
#     follows the current view (and carries no manual-order
#     information at all), or the playlist's manual order itself is
#     now reverse(B) and the list read is the manual order. The two
#     readings cannot be told apart from index, so index must never
#     be used as a sort detector. It remains in the diagnostic only
#     as a reported value, never as a classification input.
#
# What IS measurable: the end-to-end build-to-list mapping on a
# throwaway playlist that carries the SAME sort as the target. The
# user sets the throwaway's sort in Music's UI to Playlist Order
# descending (the target's reported sort), then bridge/sort-probe
# builds a known order on it and reads the result back. The mapping
# conflates insert direction, sort behaviour, and read behaviour
# into one observable quantity, which is all a build needs:
#
#   "forward":  list read after building X equals X.
#   "reversed": list read after building X equals reverse(X).
#   "other":    list read equals neither (another column sort, a
#               partial build, or any behaviour the bridge cannot
#               predict). ABORT, never build.
#
# Build/verify formulas (the single source of truth shared with the
# AppleScript handlers buildForMapping / verifyAgainst):
#
#   * To land list-read order D: duplicate D under "forward",
#     duplicate reverse(D) under "reversed". Verify the list read
#     against D, always, never against the duplicate order.
#   * This holds for applies (D = the desired order) and restores
#     (D = a list-read backup) alike, because both targets are
#     list-read orders.
#   * Display: the restore/apply goal the bridge can measure is the
#     list-read order D. If the list read is the Music view order
#     (as the diagnostic's positional agreement suggests), the
#     display order after a successful build is also D. That last
#     step is NOT proven by any script; Stage 3 of the Mac procedure
#     must eyeball the display's first/last songs after a restore.
#
# Concrete reconciliation with the real playlist, using B for the
# original backup order. The diagnostic shows the current list read
# is reverse(B) (ends confirmed; full exactness is a Stage 0 dump
# comparison, since the diagnostic prints ends only). A restore
# wants list read B again. Under the mapping model the restore
# build order is B if the sort-matched mapping is "forward", and
# reverse(B) if it is "reversed" -- and that statement holds under
# EITHER index reading: if index follows the view, index tells
# nothing and the mapping is the only authority; if index is
# manual, the current manual order is reverse(B) and the mapping
# test on a sort-matched throwaway still resolves, end to end,
# whether duplicating B or reverse(B) lands list read B. No formula
# in this model depends on what index means.
#
# The mapping is measured by the user on a throwaway and recorded
# by run.sh (sort-mapping.txt, 24-hour freshness); apply/undo refuse
# to run without a fresh mapping. The mapping is NOT measured on
# the target itself, because measuring it on the target IS a build.
# A stale or mismatched mapping (throwaway sort != target sort) is
# a wrong mapping, so the procedure requires the throwaway to carry
# the target's sort and requires re-probing whenever the target's
# sort may have changed. A failed verify never flips the mapping:
# it restores from backup and exits non-zero. Flipping on failure
# would be guessing again, and the 2026-10-28 runs are what guessing
# buys.
# ---------------------------------------------------------------------------

MAPPINGS = ("forward", "reversed", "other")


def parse_mapping(value: str) -> str:
    """Validate a sort-matched build mapping; raise on anything else."""
    if value not in MAPPINGS:
        raise ValueError(
            f"unknown playlist build mapping: {value!r} "
            f"(expected one of: {', '.join(MAPPINGS)})"
        )
    return value


def mapping_from_build_result(
    build_order: Sequence[T], list_after: Sequence[T]
) -> str:
    """Classify a sort-probe result from a known build order.

    The probe builds `build_order` on a sort-matched throwaway and
    reads back `list_after`. "forward" if the read equals the build
    order, "reversed" if it equals the exact reverse of the build
    order, "other" otherwise (including length mismatch). The probe
    build order must be chosen so that it is neither equal to nor
    the reverse of the throwaway's prior order, and must contain no
    ambiguous duplicates; the sort-probe script rotates the current
    list by one position for exactly that reason.
    """
    build_order = list(build_order)
    list_after = list(list_after)
    if len(build_order) != len(list_after):
        return "other"
    if list_after == build_order:
        return "forward"
    if list_after == reverse_list(build_order):
        return "reversed"
    return "other"


def build_for_mapping(desired: Sequence[T], mapping: str) -> list[T]:
    """Duplicate order for a build wanting list-read order `desired`.

    "forward": duplicate as-is. "reversed": duplicate in reverse
    order, because the sort-matched mapping reverses the build
    order back into `desired`. "other": raise, because building
    into an unpredictable mapping is refused, never attempted.
    """
    parse_mapping(mapping)
    if mapping == "reversed":
        return reverse_list(desired)
    if mapping == "other":
        raise ValueError(
            "cannot build with an 'other' mapping: the sort-matched "
            "probe did not return forward or reversed; set the "
            "throwaway and target sorts to Playlist Order and "
            "re-probe before building"
        )
    return list(desired)


def expected_for_mapping(desired: Sequence[T], mapping: str) -> list[T]:
    """List-read expectation after a mapping build of `desired`.

    Always `desired` itself, in both buildable mappings: verification
    compares the list read against the desired list-read order,
    never against the duplicate order. Raises for "other".
    """
    parse_mapping(mapping)
    if mapping == "other":
        raise ValueError(
            "cannot verify an 'other' mapping: re-probe on a "
            "sort-matched throwaway before building"
        )
    return list(desired)
