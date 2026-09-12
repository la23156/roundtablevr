// Deepgram aura-2 text-to-speech proxy. Keeps the Deepgram key server-side;
// returns raw audio/mpeg bytes for one clause chunk.

import { NextRequest, NextResponse } from "next/server";
import { CAST } from "@/lib/characters";
import { CURATED_VOICES } from "@/lib/characterTypes";

export const maxDuration = 30;

// Cast voices + the curated audition list from the character creator.
const VALID_VOICES = new Set([
  ...CAST.map((c) => c.voiceID),
  ...CURATED_VOICES.map((v) => v.id),
]);

export async function POST(request: NextRequest) {
  let text = "";
  let voiceID = "";
  try {
    const body = (await request.json()) as { text?: string; voiceID?: string };
    text = (body.text ?? "").trim();
    voiceID = body.voiceID ?? "";
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  if (!text || !VALID_VOICES.has(voiceID)) {
    return NextResponse.json(
      { error: "text and a valid voiceID are required" },
      { status: 400 }
    );
  }

  const key = process.env.DEEPGRAM_API_KEY;
  if (!key) {
    return NextResponse.json(
      { error: "DEEPGRAM_API_KEY is not configured" },
      { status: 500 }
    );
  }

  const url = `https://api.deepgram.com/v1/speak?model=${encodeURIComponent(
    voiceID
  )}&encoding=mp3`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Token ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ text: text.slice(0, 1900) }),
  });

  if (!res.ok) {
    const body = await res.text();
    return NextResponse.json(
      { error: `Deepgram TTS ${res.status}: ${body.slice(0, 200)}` },
      { status: 502 }
    );
  }

  const audio = await res.arrayBuffer();
  return new NextResponse(audio, {
    status: 200,
    headers: {
      "Content-Type": "audio/mpeg",
      "Cache-Control": "no-store",
    },
  });
}
