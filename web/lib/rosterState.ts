// Roster seat/tray state (workstream B) — PURE functions, no React, no DOM.
// The CardTable component applies these; a node script can unit-test them.
//
// Model: `Seats` is a fixed-length array of SEAT_COUNT slots around the
// table; each slot holds a character id or null. Slot 0 is the moderator's
// chair: the moderator is pre-seated there and can never be moved or
// unseated. Every roster character not currently seated lives in the tray.

export const SEAT_COUNT = 5;
export const MIN_SEATED = 3; // counting the moderator
export const MODERATOR_ID = "elowen";

export type Seats = ReadonlyArray<string | null>;

/** Fresh table: moderator locked into slot 0, everything else empty. */
export function initialSeats(moderatorId: string = MODERATOR_ID): Seats {
  const seats: (string | null)[] = new Array(SEAT_COUNT).fill(null);
  seats[0] = moderatorId;
  return seats;
}

/** Seated ids in seat order (nulls skipped). */
export function seatedIds(seats: Seats): string[] {
  return seats.filter((id): id is string => id !== null);
}

export function isSeated(seats: Seats, id: string): boolean {
  return seats.includes(id);
}

export function seatIndexOf(seats: Seats, id: string): number {
  return seats.indexOf(id);
}

/** Lowest-index empty slot, or -1 when the table is full. */
export function firstFreeSeat(seats: Seats): number {
  return seats.findIndex((id) => id === null);
}

/** Ids from `allIds` that are not seated, in roster order (the tray). */
export function trayIds(allIds: string[], seats: Seats): string[] {
  return allIds.filter((id) => !seats.includes(id));
}

/**
 * Seat `id` at `seatIndex` (or the first free slot when omitted/-1).
 * No-ops (returns the SAME array reference) when: the slot is taken by
 * someone else, the slot index is invalid, the moderator is being moved,
 * or there is no free slot. A seated non-moderator moves between slots.
 */
export function seat(seats: Seats, id: string, seatIndex = -1): Seats {
  if (seats[0] === id) return seats; // moderator never moves
  const target = seatIndex >= 0 ? seatIndex : firstFreeSeat(seats);
  if (target < 0 || target >= SEAT_COUNT) return seats;
  if (seats[target] === id) return seats; // already there
  if (seats[target] !== null) return seats; // occupied by someone else
  const next = seats.map((s) => (s === id ? null : s)); // lift from old slot
  next[target] = id;
  return next;
}

/** Remove `id` from the table. Moderator (slot 0) is locked: no-op. */
export function unseat(seats: Seats, id: string): Seats {
  const idx = seats.indexOf(id);
  if (idx <= 0) return seats; // not seated, or the locked moderator chair
  const next = [...seats];
  next[idx] = null;
  return next;
}

/** Click-to-toggle fallback: seated → unseat; in tray → first free slot. */
export function toggleSeat(seats: Seats, id: string): Seats {
  return isSeated(seats, id) ? unseat(seats, id) : seat(seats, id);
}

/** A discussion needs 3–5 at the table, moderator included. */
export function canStart(seats: Seats): boolean {
  const n = seatedIds(seats).length;
  return seats[0] !== null && n >= MIN_SEATED && n <= SEAT_COUNT;
}
