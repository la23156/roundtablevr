// The director: writes every character's next line, one turn at a time.
// Stateless port of roundtable/Session/ConversationDirector.swift — the client
// owns the transcript, summary, facts block, and current-page context and
// sends them with every request.

import { NextRequest, NextResponse } from "next/server";
import { CAST } from "@/lib/characters";
import {
  Direction,
  DirectorTurn,
  EMOTIONS,
  GESTURES,
  TurnRequest,
  promptLine,
} from "@/lib/types";
import { DIRECTOR_MODEL, FAST_MODEL, structuredResponse } from "@/lib/openai";

export const maxDuration = 60;

// ---- Directed mode (workstream C) -----------------------------------------

/** Extra system-prompt block, present only when the request carries a Direction.
 *  Turns the moderator into a teacher working through user-defined key points. */
function directedBlock(
  direction: Direction,
  coveredPoints: number[],
  turnsSinceProgress: number
): string {
  const moderator = CAST.find((c) => c.isModerator);
  const modName = moderator?.name ?? "the moderator";
  const covered = new Set(coveredPoints);
  const pointLines = direction.keyPoints
    .map(
      (p, i) =>
        `  index ${i} ${covered.has(i) ? "[ALREADY COVERED]" : "[not yet covered]"}: ${p}`
    )
    .join("\n");
  const nextIdx = direction.keyPoints.findIndex((_, i) => !covered.has(i));
  const strictnessLine =
    direction.strictness === "firm"
      ? `Strictness: FIRM — when the discussion drifts from the goal, the moderator intervenes promptly and directly: politely cuts in, names the digression, and redirects to the next key point.`
      : `Strictness: GENTLE — when the discussion drifts from the goal, the moderator steers with a light touch, gracefully bridging what was just said back toward the goal.`;
  const checkInLine =
    direction.checkInStyle === "perPoint"
      ? `Check-in cadence: after EVERY key point lands, the moderator checks the user's understanding of it.`
      : `Check-in cadence: PERIODIC — the moderator checks the user's understanding every couple of key points, not after every single one.`;

  return `
DIRECTED SESSION — the user has defined a direction for tonight's discussion, and ${modName} (the MODERATOR) is also a TEACHER, personally responsible for the USER's understanding.

GOAL OF THE SESSION: ${direction.goal}

KEY POINTS (guide the table through them in roughly this order — via natural discussion; NEVER recite or enumerate this list aloud):
${pointLines}

TEACHING RULES:
- The characters explore each key point substantively through their own voices and disagreements; the moderator nudges the discussion from one point toward the next.
- covered_point: this drives the user's live progress checklist, and every point must eventually be credited. When the turn you write lands the core insight of a not-yet-covered key point — or completes substance the last few turns built up — set covered_point to that index ON THIS TURN. Two or three genuinely substantive turns on a point's core idea is enough to credit it; do not wait for a perfect moment. A mere name-drop is not enough. One point max per turn, else null. Never an index marked [ALREADY COVERED].
- When a key point has JUST been covered (the previous turn, or a director's note says so), the MODERATOR takes the next turn, faces the USER (look_target "user", invites_user true), and checks their understanding of that specific point — one warm, conversational question about the substance ("Does that distinction land for you?" not "Can you repeat point 3?"). ${checkInLine}
- on_track: report honestly whether the discussion serves the goal AFTER the turn you write. Set FALSE whenever the majority of the turn is tangent material relative to the goal (a fad story, a joke chain, an unrelated debate) — even if it ends with a graceful pivot back. Set true only when the turn's main content genuinely works the goal or a key point, including a turn whose main content is steering the table back.
- ${strictnessLine}
- If the DIRECTOR'S NOTE carries a steering directive, obey it exactly this turn.${
    turnsSinceProgress > 0
      ? `\n- It has been ${turnsSinceProgress} turns since the last key point landed.${
          nextIdx >= 0
            ? ` The next point to work toward is index ${nextIdx}.`
            : ""
        }`
      : ""
  }${
    nextIdx < 0
      ? `\n- Every key point has been covered: the moderator moves the session toward a natural synthesis and closing reflections on the goal.`
      : ""
  }`;
}

// ---------------------------------------------------------------------------

function systemPrompt(
  summary: string,
  page: TurnRequest["currentPage"],
  factsBlock?: string | null,
  directed?: string
): string {
  const castSheets = CAST.map(
    (spec) =>
      `${spec.id}: ${spec.name} — ${spec.archetype}${
        spec.isModerator ? " (MODERATOR)" : ""
      }\n  Worldview: ${spec.worldview}\n  Voice & style: ${spec.speechStyle}`
  ).join("\n");

  const pageText = (page.text || "(no extractable text on this page)").slice(
    0,
    2800
  );

  return `You are the director of a lively Harkness-table seminar in a cozy antique study. \
You write every character's next line, one turn at a time. The human user sits at the \
table and can speak at any moment; they are a full participant called USER.

TONIGHT'S SUBJECT: The group is examining a document the user uploaded — typically an \
investment or pitch deck. They weigh the opportunity like a seminar of skeptical-but-curious \
investors: what's the actual thesis, what would have to be true for it to work, where the \
numbers are soft, what's genuinely exciting, and what history and first principles say about it.

DOCUMENT SUMMARY:
${summary || "(no summary available yet)"}

CURRENTLY DISPLAYED PAGE: page ${page.number} of ${page.total}
TEXT OF THE DISPLAYED PAGE:
${pageText}

THE CAST:
${castSheets}

HARD RULES:
- A turn is 1-3 SHORT spoken sentences. Never a monologue. Contractions, spoken rhythm.
- React to what was JUST said; characters address each other by name and disagree productively.
- Never have the same character speak twice in a row unless directed.
- The moderator keeps momentum: redirects, sharpens, occasionally summarizes in one line.
- Invite the user in at most once every ~6 turns ("What do you think?") — set invites_user true then.
- When the user spoke, the first response engages their point directly and by name ("you").
- insight: a 3-6 word title ONLY for genuinely striking ideas (max ~1 in 4 turns), else null.
- No stage directions, no asterisks, no emoji — pure spoken dialogue in \`text\`.
- The characters are discussing the uploaded document. They know the summary above and the \
page currently on the user's screen; ground claims in concrete details from the page text \
("this slide", "the number on page ${page.number}") whenever relevant.
- When a [NOTE] in the transcript says the user turned to a new page, the next speaker \
reacts to the new page naturally — a beat of acknowledgment, then substance.
- Skeptical is not hostile: they genuinely want to find out whether this is a good investment.
${factsBlock ? `\n${factsBlock}` : ""}${directed ?? ""}`;
}

function inputBlock(req: TurnRequest): string {
  const lines = req.transcript.slice(-40).map(promptLine).join("\n");
  const directive =
    req.directive ||
    (req.userUtterance
      ? "The user just spoke. The most fitting character responds to their point directly, by name."
      : "Continue the discussion naturally.");
  return `TRANSCRIPT SO FAR:
${lines.length ? lines : "(the table has just sat down; nothing said yet)"}

DIRECTOR'S NOTE: ${directive}

Write the next turn now.`;
}

export async function POST(request: NextRequest) {
  let body: TurnRequest;
  try {
    body = (await request.json()) as TurnRequest;
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  if (!body.currentPage || !Array.isArray(body.transcript)) {
    return NextResponse.json(
      { error: "transcript and currentPage are required" },
      { status: 400 }
    );
  }

  // The user's utterance joins the transcript before the director writes.
  const transcript = [...body.transcript];
  if (body.userUtterance?.trim()) {
    transcript.push({ kind: "user", text: body.userUtterance.trim() });
  }

  // Directed mode is active only when a well-formed direction rides along.
  const direction =
    body.direction &&
    typeof body.direction.goal === "string" &&
    body.direction.goal.trim() &&
    Array.isArray(body.direction.keyPoints) &&
    body.direction.keyPoints.length > 0
      ? body.direction
      : null;
  const coveredPoints = Array.isArray(body.coveredPoints)
    ? body.coveredPoints.filter((n) => Number.isInteger(n))
    : [];
  const turnsSinceProgress =
    typeof body.turnsSinceProgress === "number" ? body.turnsSinceProgress : 0;

  const castIDs = CAST.map((c) => c.id);
  const schema: Record<string, unknown> = {
    type: "object",
    properties: {
      speaker: { type: "string", enum: castIDs },
      text: { type: "string" },
      emotion: { type: "string", enum: [...EMOTIONS] },
      look_target: { type: "string", enum: [...castIDs, "user", "table"] },
      gesture: { type: "string", enum: [...GESTURES] },
      insight: { type: ["string", "null"] },
      invites_user: { type: "boolean" },
      // covered_point / on_track are appended below only in directed mode so
      // the schema (and behavior) is byte-identical when direction is absent.
    },
    required: [
      "speaker",
      "text",
      "emotion",
      "look_target",
      "gesture",
      "insight",
      "invites_user",
    ],
    additionalProperties: false,
  };
  if (direction) {
    const props = schema.properties as Record<string, unknown>;
    props.covered_point = {
      type: ["integer", "null"],
      description:
        "Index of the key point newly and substantively covered THIS turn, else null.",
    };
    props.on_track = {
      type: "boolean",
      description: "Whether the discussion is still serving the session goal.",
    };
    (schema.required as string[]).push("covered_point", "on_track");
  }

  try {
    const turn = await structuredResponse<DirectorTurn>({
      model: body.fast ? FAST_MODEL : DIRECTOR_MODEL,
      instructions: systemPrompt(
        body.summary ?? "",
        body.currentPage,
        body.factsBlock,
        direction
          ? directedBlock(direction, coveredPoints, turnsSinceProgress)
          : undefined
      ),
      input: inputBlock({ ...body, transcript }),
      schemaName: "roundtable_turn",
      schema,
    });
    return NextResponse.json(turn);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Turn failed";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
