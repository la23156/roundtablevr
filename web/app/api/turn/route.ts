// The director: writes every character's next line, one turn at a time.
// Stateless port of roundtable/Session/ConversationDirector.swift — the client
// owns the transcript, summary, facts block, and current-page context and
// sends them with every request.

import { NextRequest, NextResponse } from "next/server";
import { CAST } from "@/lib/characters";
import {
  DirectorTurn,
  EMOTIONS,
  GESTURES,
  TurnRequest,
  promptLine,
} from "@/lib/types";
import { DIRECTOR_MODEL, FAST_MODEL, structuredResponse } from "@/lib/openai";

export const maxDuration = 60;

function systemPrompt(
  summary: string,
  page: TurnRequest["currentPage"],
  factsBlock?: string | null
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
${factsBlock ? `\n${factsBlock}` : ""}`;
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

  const castIDs = CAST.map((c) => c.id);
  const schema = {
    type: "object",
    properties: {
      speaker: { type: "string", enum: castIDs },
      text: { type: "string" },
      emotion: { type: "string", enum: [...EMOTIONS] },
      look_target: { type: "string", enum: [...castIDs, "user", "table"] },
      gesture: { type: "string", enum: [...GESTURES] },
      insight: { type: ["string", "null"] },
      invites_user: { type: "boolean" },
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

  try {
    const turn = await structuredResponse<DirectorTurn>({
      model: body.fast ? FAST_MODEL : DIRECTOR_MODEL,
      instructions: systemPrompt(
        body.summary ?? "",
        body.currentPage,
        body.factsBlock
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
