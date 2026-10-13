// The browser tutorial game's script: a direct port of the Vision Pro
// tutorial (roundtable/Session/TutorialScript.swift) — same story, same
// five gates, same lines, same scoring economy.

export interface GuideGate {
  /** What the moment needs ("They've noticed the weather…"). */
  title: string;
  /** Suggested lines shown on the board. */
  suggestions: string[];
  /** A sent line counts if it contains ANY of these (lowercased). Empty = any ≥4-word question. */
  keywords: string[];
  /** Tutor's hint after a couple of near-misses. */
  nudge: string;
  /** One-line pedagogy note shown after the pass (the teacher-training value). */
  whyItWorks: string;
}

export interface Student {
  id: string;
  name: string;
  archetype: string;
  voiceID: string;
  /** Accent color for the avatar chip + speech bubble trim. */
  color: string;
}

export interface StudentTurn {
  speaker: string; // student id, or "tutor"
  text: string;
  /** 1-based realization node this line lands, if any. */
  coveredNode?: number;
  /** Node the discussion is circling + how close (0–0.95). */
  closestNode?: number;
  closeness?: number;
  /** This line is aimed at the teacher (Tyler's deflection). */
  deflection?: boolean;
  /** Conversation-web edge drawn when this line plays (from previous speaker). */
}

export const STUDENTS: Student[] = [
  { id: "jayden", name: "Jayden", archetype: "The Monopolizer", voiceID: "aura-2-draco-en", color: "#c47f3a" },
  { id: "june", name: "June", archetype: "Solid", voiceID: "aura-2-aurora-en", color: "#5a9e6f" },
  { id: "tyler", name: "Tyler", archetype: "Confidently Incorrect", voiceID: "aura-2-zeus-en", color: "#b05c5c" },
  { id: "maddie", name: "Maddie", archetype: "The Echo", voiceID: "aura-2-luna-en", color: "#8d7bb0" },
  { id: "wren", name: "Wren", archetype: "The Ghost", voiceID: "aura-2-theia-en", color: "#5b8aa8" },
];

export const NARRATOR_VOICE = "aura-2-hera-en";

export const NODES = [
  "The window turns the tone",
  "Change hits the body first",
  "Line one loads the last line",
];

// Scoring — mirrors HarknessScore in the app. Perfect run = 400.
export const SCORE = {
  nodeReached: 100,
  silenceHeld: 40,
  deflectionPassed: 30,
  goodMove: 10,
  rescue: -20,
  lecturingPenalty: -40,
};

// What's "on the board": one short public-domain excerpt per page of
// Chopin's "The Story of an Hour" (1894).
export const PAGES = [
  {
    label: "Page 1",
    excerpt:
      "Knowing that Mrs. Mallard was afflicted with a heart trouble, great care was taken to break to her as gently as possible the news of her husband's death… She wept at once, with sudden, wild abandonment, in her sister's arms.",
  },
  {
    label: "Page 2",
    excerpt:
      "There stood, facing the open window, a comfortable, roomy armchair… She could see in the open square before her house the tops of trees that were all aquiver with the new spring life. The delicious breath of rain was in the air… and countless sparrows were twittering in the eaves.",
  },
  {
    label: "Page 3",
    excerpt:
      "When she abandoned herself a little whispered word escaped her slightly parted lips. She said it over and over under her breath: \"free, free, free!\"… Her pulses beat fast, and the coursing blood warmed and relaxed every inch of her body.",
  },
  {
    label: "Page 4",
    excerpt:
      "Someone was opening the front door with a latchkey. It was Brently Mallard who entered… But Richards was too late. When the doctors came they said she had died of heart disease — of the joy that kills.",
  },
];

// ---- The gates (the player's moves) — verbatim from the app.

export const launchGate: GuideGate = {
  title: "Launch the discussion with a catalyst — one open question, no right answer.",
  suggestions: [
    "What changes in this story — and when, exactly?",
    "Why does Chopin give us Louise's heart trouble in the very first line?",
  ],
  keywords: [],
  nudge: "Any open question works — send one off the board, in your own words if you like.",
  whyItWorks:
    "That's a catalyst question: open, text-anchored, no right answer. It hands the class a direction without an opinion to agree with.",
};

export const windowGate: GuideGate = {
  title: "They've noticed the weather — but not what it's doing to the story. Steer them to the window.",
  suggestions: [
    "What does Louise actually see from that chair?",
    "Where exactly does the mood of the story turn?",
  ],
  keywords: [
    "see", "sees", "chair", "window", "mood", "turn", "turns",
    "outside", "looking", "spring", "feel", "shift",
  ],
  nudge: "Point them at what she sees — the chair faces an open window.",
  whyItWorks:
    "A textual tether: instead of explaining the tone shift, you sent every head back to the page — and a student found it herself.",
};

export const deflectGate: GuideGate = {
  title: "Tyler just asked YOU. Don't answer — hand the question back to the table.",
  suggestions: [
    "I don't know — what does the table think?",
    "Where in the text do you see that?",
  ],
  keywords: [
    "table", "think", "thinks", "text", "where", "class",
    "everyone", "else", "others", "you all", "anyone",
  ],
  nudge: "Never answer a deflection. Ask the table what they think.",
  whyItWorks:
    "The redirect. Answer a deflection and you become the room's oracle; hand it back and the class keeps owning the thinking.",
};

export const bodyGate: GuideGate = {
  title: "They're circling her feelings — but Chopin hid the change somewhere specific. Send them to her body.",
  suggestions: [
    "What is Louise's body doing in this scene?",
    "Can you find the change before she ever says 'free'?",
  ],
  keywords: [
    "body", "physical", "pulse", "pulses", "blood", "hands",
    "breath", "skin", "doing", "physically",
  ],
  nudge: "Her pulses, her blood — ask what her body is doing.",
  whyItWorks:
    "A precise question reaches the quiet ones. Wren never volunteers — but she'd been sitting on that answer the whole time.",
};

export const plantGate: GuideGate = {
  title: "Last note. The ending only works because of page one. Send them back to the first line.",
  suggestions: [
    "Why did Chopin tell us about her heart in the very first line?",
    "Reread the first sentence — what did it promise?",
  ],
  keywords: [
    "first", "heart", "beginning", "start", "opening",
    "sentence", "line", "promise", "promised", "back",
  ],
  nudge: "Send them back to the very first sentence of the story.",
  whyItWorks:
    "Structure questions make writers. The class just discovered foreshadowing by rereading — nobody had to define the term.",
};

// Words that mean the teacher ANSWERED Tyler instead of redirecting —
// the Lecturing Penalty branch of the deflection gate.
export const LECTURE_WORDS = [
  "yes", "no,", "no.", "she is", "she's not", "actually", "villain",
  "not a villain", "correct", "wrong", "exactly",
];

// ---- Student lines, in play order — verbatim from the app.

export const TURNS: Record<string, StudentTurn> = {
  openerJayden: {
    speaker: "jayden",
    text: "Okay so, husband dies in a train crash, wife cries, goes upstairs. Pretty standard sad story so far, honestly.",
    closestNode: 1,
    closeness: 0.3,
  },
  weatherJayden: {
    speaker: "jayden",
    text: "Page two is weird though — sparrows, spring, patches of blue sky? Her husband just died. It's the wrong weather.",
    closestNode: 1,
    closeness: 0.6,
  },
  windowJune: {
    speaker: "june",
    text: "Wait — that's it. She's facing the open window, and everything through it is new spring life. The story's whole mood turns right there, before Louise herself feels anything. The window changes the tone.",
    coveredNode: 1,
  },
  tylerDeflection: {
    speaker: "tyler",
    text: "Okay but page three — 'free, body and soul free'? She's celebrating his death. So she's the villain, right, teacher?",
    deflection: true,
  },
  maddieCircling: {
    speaker: "maddie",
    text: "I don't think she's a villain, she's just like… feeling a lot of feelings? It's confusing what she even feels.",
    closestNode: 2,
    closeness: 0.5,
  },
  wrenBody: {
    speaker: "wren",
    text: "…Her body answers before she does. Her pulses beat fast, the blood warms and relaxes every inch of her. Chopin writes the change into Louise's body before Louise can even name it. She's not deciding to be free — she's discovering she already is.",
    coveredNode: 2,
  },
  endingJayden: {
    speaker: "jayden",
    text: "And then the husband just walks in with his umbrella and she drops dead. The doctors say 'the joy that kills.' Ironic, I guess?",
    closestNode: 3,
    closeness: 0.7,
  },
  plantJune: {
    speaker: "june",
    text: "Oh — the first line. 'Afflicted with a heart trouble.' The doctors misread her death, but we can't, because Chopin loaded that sentence before anything happened. The ending was planted in the opening.",
    coveredNode: 3,
  },
};

// ---- Narrator (Tutor) lines.

export const TUTOR = {
  welcome:
    "Welcome to HarknessAI. Tonight your class discusses Kate Chopin's \"The Story of an Hour\" — page one is on the board, and they've all done the reading.",
  intention:
    "Here is your intention. By the end, the students should discover three things on their own:",
  brief1: "One — the open window turns the story's tone.",
  brief2: "Two — Louise's change is written in her body before her mind.",
  brief3: "Three — the famous last line was planted in the very first.",
  rule:
    "You never say these aloud — your art is asking the question that lets a student arrive. A note pulses as the class gets close, and turns green when they land it. When a board appears, it's your move.",
  afterLaunch:
    "Good. Now lean back and say nothing — silence is what makes a student start.",
  rescued:
    "You rescued them — in this room, silence is your sharpest tool. Once more: quiet, and let it stretch.",
  silenceHeld: "You held it — and look who finally couldn't stand the quiet.",
  note1: "Note one is green — they found it, and all you did was ask.",
  lectured:
    "You answered him — and the room just learned that the teacher settles arguments. That's the Lecturing Penalty. Try again: hand it back.",
  note2:
    "That was Wren — the quiet one. The right question reaches students who never volunteer. Note two is green.",
  outro:
    "All three notes are green — and every realization came out of a student's mouth, not yours. That is a Harkness class.",
};
