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
}
