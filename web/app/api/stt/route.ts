// Deepgram speech-to-text proxy for one recorded utterance (webm/opus blob).
//
// Streaming context: the ideal path is Deepgram Flux over a browser WebSocket
// with a short-lived token from /v1/auth/grant — but this account's API key
// lacks that scope (verified: FORBIDDEN), and Vercel serverless functions
// cannot proxy WebSockets. So the client does VAD locally, records complete
// utterances, and posts them here for nova-3 transcription (~300-500 ms).

import { NextRequest, NextResponse } from "next/server";

export const maxDuration = 30;

export async function POST(request: NextRequest) {
  const key = process.env.DEEPGRAM_API_KEY;
  if (!key) {
    return NextResponse.json(
      { error: "DEEPGRAM_API_KEY is not configured" },
      { status: 500 }
    );
  }

  const audio = await request.arrayBuffer();
  if (audio.byteLength < 1000) {
    return NextResponse.json({ transcript: "" });
  }
  if (audio.byteLength > 8_000_000) {
    return NextResponse.json({ error: "Audio too large" }, { status: 413 });
  }

  const contentType = request.headers.get("content-type") || "audio/webm";
  const res = await fetch(
    "https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true",
    {
      method: "POST",
      headers: { Authorization: `Token ${key}`, "Content-Type": contentType },
      body: audio,
    }
  );

  if (!res.ok) {
    const body = await res.text();
    return NextResponse.json(
      { error: `Deepgram STT ${res.status}: ${body.slice(0, 200)}` },
      { status: 502 }
    );
  }

  const data = (await res.json()) as {
    results?: {
      channels?: Array<{
        alternatives?: Array<{ transcript?: string }>;
      }>;
    };
  };
  const transcript =
    data.results?.channels?.[0]?.alternatives?.[0]?.transcript ?? "";
  return NextResponse.json({ transcript });
}
