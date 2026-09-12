// POST /api/portrait { appearance } — generate a tarot-style portrait via
// FAL flux/schnell and return it as a base64 data URL for client preview.
// The confirmed portrait is uploaded to Blob by POST /api/characters.

import { NextRequest, NextResponse } from "next/server";
import { generatePortrait } from "@/lib/portraitGen";

export const maxDuration = 60;

export async function POST(request: NextRequest) {
  let appearance = "";
  try {
    const body = (await request.json()) as { appearance?: string };
    appearance = (body.appearance ?? "").trim();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  if (!appearance || appearance.length > 600) {
    return NextResponse.json(
      { error: "appearance (1–600 chars) is required" },
      { status: 400 }
    );
  }

  try {
    const { bytes, contentType } = await generatePortrait(appearance);
    const dataURL = `data:${contentType};base64,${bytes.toString("base64")}`;
    return NextResponse.json(
      { dataURL },
      { headers: { "Cache-Control": "no-store" } }
    );
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Generation failed" },
      { status: 502 }
    );
  }
}
