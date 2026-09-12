// Ported from roundtable/Session/TurnModels.swift

export const EMOTIONS = [
  "neutral",
  "amused",
  "passionate",
  "skeptical",
  "thoughtful",
  "surprised",
  "warm",
] as const;
export type Emotion = (typeof EMOTIONS)[number];

export const GESTURES = [
  "none",
  "nod",
  "head_shake",
  "lean_in",
  "hand_open",
  "chin_stroke",
  "shrug",
] as const;
export type Gesture = (typeof GESTURES)[number];

/** One conversational turn as emitted by the director LLM (strict JSON schema). */
export interface DirectorTurn {
  speaker: string; // cast id
  text: string;
  emotion: Emotion;
  look_target: string; // cast id, "user", or "table"
  gesture: Gesture;
  insight: string | null; // 3-6 word gem label, else null
  invites_user: boolean;
  // Directed-mode extensions — present only when the request carried a Direction.
  covered_point?: number | null; // index into Direction.keyPoints newly covered THIS turn
  on_track?: boolean; // is the discussion still serving the direction's goal?
}

/** A user-defined direction for a directed (taught/moderated) session. */
export interface Direction {
  goal: string;
  keyPoints: string[]; // 3-7, ordered
  strictness: "gentle" | "firm";
  checkInStyle: "perPoint" | "periodic";
}

/** Entries in the running transcript handed back to the director. */
export type TranscriptEntry =
  | {
      kind: "character";
      id: string;
      name: string;
      text: string;
      interrupted: boolean;
    }
  | { kind: "user"; text: string }
  | { kind: "note"; text: string }; // system note, e.g. a page turn

export function promptLine(entry: TranscriptEntry): string {
  switch (entry.kind) {
    case "character":
      return `[${entry.name.toUpperCase()}]: ${entry.text}${
        entry.interrupted ? " (interrupted mid-sentence)" : ""
      }`;
    case "user":
      return `[USER]: ${entry.text}`;
    case "note":
      return `[NOTE]: ${entry.text}`;
  }
}

export interface PageContext {
  number: number;
  total: number;
  text: string;
}

/** Request body for POST /api/turn. */
export interface TurnRequest {
  transcript: TranscriptEntry[];
  summary: string;
  factsBlock?: string | null;
  currentPage: PageContext;
  directive?: string;
  userUtterance?: string;
  fast?: boolean;
  /** Seated roster (workstream B): ids of the characters at the table, in
   *  seat order. Absent/empty means the classic built-in five. */
  castIds?: string[];
  // Directed-mode state (client-owned; all optional — absent means classic mode).
  direction?: Direction | null;
  coveredPoints?: number[]; // indexes into direction.keyPoints already covered
  turnsSinceProgress?: number; // turns since a key point last landed
}
