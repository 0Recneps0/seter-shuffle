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
