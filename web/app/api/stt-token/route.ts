// Attempts to mint a short-lived Deepgram token for direct browser streaming
// (Flux). With the current account key this returns { available: false } —
// the key lacks the auth-grant scope — and the client falls back to
// utterance-mode STT via /api/stt. If the key is later upgraded, this route
// starts returning tokens with no code changes.

import { NextResponse } from "next/server";

export async function GET() {
  const key = process.env.DEEPGRAM_API_KEY;
  if (!key) return NextResponse.json({ available: false });

  try {
    const res = await fetch("https://api.deepgram.com/v1/auth/grant", {
      method: "POST",
      headers: {
        Authorization: `Token ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ttl_seconds: 60 }),
    });
    if (!res.ok) return NextResponse.json({ available: false });
    const data = (await res.json()) as {
      access_token?: string;
      expires_in?: number;
    };
    if (!data.access_token) return NextResponse.json({ available: false });
    return NextResponse.json({
      available: true,
      accessToken: data.access_token,
      expiresIn: data.expires_in ?? 60,
    });
  } catch {
    return NextResponse.json({ available: false });
  }
}
