// Summarizes the uploaded document (~300 tokens) and extracts key entities
// for the fresh-facts web search. Runs once per upload, client caches result.

import { NextRequest, NextResponse } from "next/server";
import { FAST_MODEL, structuredResponse } from "@/lib/openai";

export const maxDuration = 60;

interface SummarizeResult {
  summary: string;
  entities: string[];
}

export async function POST(request: NextRequest) {
  let text: string;
  try {
    const body = (await request.json()) as { text?: string };
    text = (body.text ?? "").trim();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  if (!text) {
    return NextResponse.json({ error: "text is required" }, { status: 400 });
  }

  const schema = {
    type: "object",
    properties: {
      summary: { type: "string" },
      entities: { type: "array", items: { type: "string" } },
    },
    required: ["summary", "entities"],
    additionalProperties: false,
  };

  try {
    const result = await structuredResponse<SummarizeResult>({
      model: FAST_MODEL,
      instructions: `You prepare briefing notes for a panel of investors about to discuss an uploaded \
document (usually an investment or pitch deck). Write a tight ~300-token summary: what the \
document is, the core thesis or ask, the key numbers (market size, revenue, raise, valuation \
if present), the team, and anything unusual. Then list 3-6 key searchable entities \
(company names, products, founders, sectors) for a web search on fresh context.`,
      input: `DOCUMENT TEXT (may be truncated):\n${text.slice(0, 60000)}`,
      schemaName: "doc_briefing",
      schema,
    });
    return NextResponse.json(result);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Summarize failed";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
