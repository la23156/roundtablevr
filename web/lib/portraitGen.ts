// Portrait generation via FAL flux/schnell — SERVER-SIDE ONLY.
// Every portrait shares the locked "antique oil painting" style prefix so
// custom characters sit next to the built-in five without visual whiplash.

import { PORTRAIT_STYLE_PREFIX } from "@/lib/characterTypes";

export interface GeneratedPortrait {
  bytes: Buffer;
  contentType: string; // e.g. "image/jpeg" or "image/png"
}

interface FalImage {
  url?: string;
  content_type?: string;
}

interface FalEnvelope {
  images?: FalImage[];
}

export async function generatePortrait(
  appearance: string
): Promise<GeneratedPortrait> {
  const key = process.env.FAL_API_KEY;
  if (!key) throw new Error("FAL_API_KEY is not configured");

  const prompt = PORTRAIT_STYLE_PREFIX + appearance.trim();
  const res = await fetch("https://fal.run/fal-ai/flux/schnell", {
    method: "POST",
    headers: {
      Authorization: `Key ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      prompt,
      image_size: "portrait_4_3", // 768×1024 — matches the tarot-card face
      num_images: 1,
      num_inference_steps: 4,
      enable_safety_checker: true,
    }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`FAL HTTP ${res.status}: ${body.slice(0, 300)}`);
  }

  const envelope = (await res.json()) as FalEnvelope;
  const image = envelope.images?.[0];
  if (!image?.url) throw new Error("FAL response contained no image");

  // sync responses can inline a data URI; hosted URLs need a second fetch.
  if (image.url.startsWith("data:")) {
    const match = /^data:([^;,]+);base64,(.+)$/.exec(image.url);
    if (!match) throw new Error("FAL returned an unparseable data URI");
    return {
      bytes: Buffer.from(match[2], "base64"),
      contentType: match[1],
    };
  }

  const imgRes = await fetch(image.url);
  if (!imgRes.ok) throw new Error(`FAL image fetch HTTP ${imgRes.status}`);
  return {
    bytes: Buffer.from(await imgRes.arrayBuffer()),
    contentType:
      imgRes.headers.get("content-type") ??
      image.content_type ??
      "image/jpeg",
  };
}
