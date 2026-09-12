// Character-creation platform (workstream A) — shared types + static data.
// Safe to import from both server and client code (no server-only deps).

export type BaseBody =
  | "brunette"
  | "preview"
  | "avaturn"
  | "avatarsdk"
  | "mpfb";

export interface CharacterDef {
  id: string;
  name: string;
  archetype: string;
  bio: string;
  worldview: string;
  speechStyle: string;
  voiceID: string; // Deepgram aura-2 voice model
  tintHex: string; // e.g. "#b48ede"
  baseBody: BaseBody; // 3D body used for the character in VR
  portraitURL: string; // "/portraits/x.jpg" (built-in) or Blob URL (custom)
  builtIn: boolean;
  isModerator: boolean;
  createdAt: string; // ISO-8601
}

export const BASE_BODIES: Array<{
  id: BaseBody;
  label: string;
  /** Built-in portrait used as a visual stand-in in the picker. */
  standIn: string;
}> = [
  { id: "brunette", label: "Brunette", standIn: "/portraits/elowen.jpg" },
  { id: "preview", label: "Preview", standIn: "/portraits/marcus.jpg" },
  { id: "avaturn", label: "Avaturn", standIn: "/portraits/zara.jpg" },
  { id: "avatarsdk", label: "Avatar SDK", standIn: "/portraits/dev.jpg" },
  { id: "mpfb", label: "MPFB", standIn: "/portraits/nadia.jpg" },
];

/** Curated Deepgram aura-2 voices. Every entry validated with a real
 *  /v1/speak call (all HTTP 200) on 2026-09-12. Mixed genders + accents. */
export const CURATED_VOICES: Array<{
  id: string;
  label: string;
  blurb: string; // gender · accent · character
}> = [
  { id: "aura-2-hera-en", label: "Hera", blurb: "feminine · American · smooth, warm, professional" },
  { id: "aura-2-arcas-en", label: "Arcas", blurb: "masculine · American · natural, smooth, clear" },
  { id: "aura-2-aurora-en", label: "Aurora", blurb: "feminine · American · cheerful, expressive, energetic" },
  { id: "aura-2-orion-en", label: "Orion", blurb: "masculine · American · approachable, comfortable, calm" },
  { id: "aura-2-luna-en", label: "Luna", blurb: "feminine · American · friendly, natural, engaging" },
  { id: "aura-2-draco-en", label: "Draco", blurb: "masculine · British · warm, approachable, trustworthy" },
  { id: "aura-2-pandora-en", label: "Pandora", blurb: "feminine · British · smooth, calm, melodic" },
  { id: "aura-2-hyperion-en", label: "Hyperion", blurb: "masculine · Australian · caring, warm, empathetic" },
  { id: "aura-2-theia-en", label: "Theia", blurb: "feminine · Australian · expressive, polite, sincere" },
  { id: "aura-2-zeus-en", label: "Zeus", blurb: "masculine · American · deep, trustworthy, smooth" },
];

export const CURATED_VOICE_IDS = new Set(CURATED_VOICES.map((v) => v.id));

/** 8 tint presets (the 5 built-in tints + 3 extras in the same register). */
export const TINT_PRESETS = [
  "#b48ede", // wisteria (Elowen)
  "#5fc4bd", // verdigris (Marcus)
  "#e88bb1", // rose (Zara)
  "#e8a05f", // amber (Dev)
  "#8bc98b", // sage (Nadia)
  "#d9a441", // lamplight gold
  "#7fa8d9", // dusk blue
  "#c96a5a", // terracotta
];

/** LOCKED portrait style prefix — do not change without design sign-off. */
export const PORTRAIT_STYLE_PREFIX =
  "antique oil painting portrait bust, warm lamplight from the side, dark academia palette, rich amber and mahogany tones, ornate gold tarot card frame border, painterly brushwork, no text, ";

/** The built-in five, ported from CharacterRoster.swift. */
export const BUILT_IN_CHARACTERS: CharacterDef[] = [
  {
    id: "elowen",
    name: "Prof. Elowen Hart",
    archetype: "The Moderator",
    bio: "Silver-haired literature professor who keeps the table honest — and quotes poets from memory.",
    worldview:
      "Believes every big question is older than it looks; the humanities already rehearsed most of our dilemmas. Warm but rigorous; her job is to draw people out, sharpen disagreements, and keep the seminar moving.",
    speechStyle:
      "Measured, warm, occasionally quotes a poet or novelist in one line. Asks pointed questions. Never rambles.",
    voiceID: "aura-2-hera-en",
    tintHex: "#b48ede",
    baseBody: "brunette",
    portraitURL: "/portraits/elowen.jpg",
    builtIn: true,
    isModerator: true,
    createdAt: "2025-08-01T00:00:00.000Z",
  },
  {
    id: "marcus",
    name: "Marcus Vale",
    archetype: "The Skeptic",
    bio: "Dry-witted economist who wants to see the data before he believes your beautiful idea.",
    worldview:
      "Incentives explain most things people attribute to ideals. Suspicious of grand narratives; delighted by inconvenient statistics. Secretly a romantic about markets.",
    speechStyle:
      "Dry, precise, lightly sarcastic. Loves 'the numbers say otherwise'. Short sentences.",
    voiceID: "aura-2-arcas-en",
    tintHex: "#5fc4bd",
    baseBody: "preview",
    portraitURL: "/portraits/marcus.jpg",
    builtIn: true,
    isModerator: false,
    createdAt: "2025-08-01T00:00:00.000Z",
  },
  {
    id: "zara",
    name: "Zara Moon",
    archetype: "The Dreamer",
    bio: "Futurist artist convinced the future is a design problem — and we're holding the pencil.",
    worldview:
      "Technology and imagination are the same force wearing different clothes. Optimistic to a fault; believes cynicism is just fear with better PR.",
    speechStyle:
      "Exuberant, vivid imagery, jumps between big ideas, occasionally breathless. Uses metaphors constantly.",
    voiceID: "aura-2-aurora-en",
    tintHex: "#e88bb1",
    baseBody: "avaturn",
    portraitURL: "/portraits/zara.jpg",
    builtIn: true,
    isModerator: false,
    createdAt: "2025-08-01T00:00:00.000Z",
  },
  {
    id: "dev",
    name: "Dr. Dev Okafor",
    archetype: "The Physicist",
    bio: "Deadpan physicist who ruins science fiction for everyone, lovingly.",
    worldview:
      "The universe is under no obligation to be intuitive. Precision is a form of respect. Enjoys demolishing sloppy arguments, then rebuilding them better.",
    speechStyle:
      "Deadpan, exact, understated humor. Corrects units. Pauses before delivering the punchline.",
    voiceID: "aura-2-orion-en",
    tintHex: "#e8a05f",
    baseBody: "avatarsdk",
    portraitURL: "/portraits/dev.jpg",
    builtIn: true,
    isModerator: false,
    createdAt: "2025-08-01T00:00:00.000Z",
  },
  {
    id: "nadia",
    name: "Nadia Reyes",
    archetype: "The Historian",
    bio: "Storytelling historian who has seen this exact argument before — in 1848, and it went badly.",
    worldview:
      "Nothing is unprecedented; everything rhymes. Empathy for people in every era. Believes the past is the only laboratory we have for human nature.",
    speechStyle:
      "Warm storyteller, opens with 'There's a story about…', connects the present to concrete historical moments.",
    voiceID: "aura-2-luna-en",
    tintHex: "#8bc98b",
    baseBody: "mpfb",
    portraitURL: "/portraits/nadia.jpg",
    builtIn: true,
    isModerator: false,
    createdAt: "2025-08-01T00:00:00.000Z",
  },
];

export const BASE_BODY_IDS = new Set<string>(BASE_BODIES.map((b) => b.id));
