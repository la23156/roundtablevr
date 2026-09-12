// Exa web search: fetches a compact fresh-facts block for the document's key
// entities. Ported from roundtable/Services/ExaClient.swift. Fresh facts are
// a bonus, never a blocker — failures return { factsBlock: null }.

import { NextRequest, NextResponse } from "next/server";

export const maxDuration = 30;

interface ExaResult {
  title?: string;
  summary?: string;
}

export async function POST(request: NextRequest) {
  let entities: string[] = [];
  try {
    const body = (await request.json()) as { entities?: string[] };
    entities = (body.entities ?? []).filter(
      (e) => typeof e === "string" && e.trim().length > 0
    );
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  if (entities.length === 0) {
    return NextResponse.json({ factsBlock: null });
  }

  const key = process.env.EXA_API_KEY;
  if (!key) return NextResponse.json({ factsBlock: null });

  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    const res = await fetch("https://api.exa.ai/search", {
      method: "POST",
      headers: { "x-api-key": key, "Content-Type": "application/json" },
      body: JSON.stringify({
        query: entities.slice(0, 5).join(", "),
        numResults: 5,
        type: "auto",
        contents: { summary: true },
      }),
      signal: controller.signal,
    });
    clearTimeout(timer);
    if (!res.ok) return NextResponse.json({ factsBlock: null });

    const envelope = (await res.json()) as { results?: ExaResult[] };
    const facts = (envelope.results ?? [])
      .filter((r) => r.summary && r.summary.length > 0)
      .map((r) => `- ${r.title ?? "Source"}: ${r.summary!.slice(0, 400)}`);
    if (facts.length === 0) return NextResponse.json({ factsBlock: null });

    const date = new Date().toLocaleDateString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
    });
    const factsBlock = `Fresh context as of ${date} — weave these facts in naturally when relevant; never cite sources or URLs aloud:\n${facts.join(
      "\n"
    )}`;
    return NextResponse.json({ factsBlock });
  } catch {
    return NextResponse.json({ factsBlock: null });
  }
}
