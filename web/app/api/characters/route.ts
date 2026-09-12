// GET  /api/characters — built-in five + custom characters.
// POST /api/characters — create a custom character. The portrait comes from
// either `portraitDataURL` (a previously previewed /api/portrait result) or
// `appearance` text (generated server-side on save).

import { NextRequest, NextResponse } from "next/server";
import {
  BASE_BODY_IDS,
  BUILT_IN_CHARACTERS,
  CURATED_VOICE_IDS,
  type BaseBody,
  type CharacterDef,
} from "@/lib/characterTypes";
import {
  getAllCharacters,
  saveCharacter,
  uploadPortrait,
} from "@/lib/characterStore";
import { generatePortrait } from "@/lib/portraitGen";

export const maxDuration = 60;

export async function GET() {
  try {
    const characters = await getAllCharacters();
    return NextResponse.json(
      { characters },
      { headers: { "Cache-Control": "no-store" } }
    );
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Store unavailable" },
      { status: 502 }
    );
  }
}

interface CreateBody {
  name?: string;
  archetype?: string;
  bio?: string;
  worldview?: string;
  speechStyle?: string;
  voiceID?: string;
  tintHex?: string;
  baseBody?: string;
  portraitDataURL?: string;
  appearance?: string;
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function slugify(name: string): string {
  const slug = name
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 32);
  return slug || "character";
}

export async function POST(request: NextRequest) {
  let body: CreateBody;
  try {
    body = (await request.json()) as CreateBody;
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const name = str(body.name);
  const archetype = str(body.archetype);
  const bio = str(body.bio);
  const worldview = str(body.worldview);
  const speechStyle = str(body.speechStyle);
  const voiceID = str(body.voiceID);
  const tintHex = str(body.tintHex).toLowerCase();
  const baseBody = str(body.baseBody);
  const portraitDataURL = str(body.portraitDataURL);
  const appearance = str(body.appearance);

  const problems: string[] = [];
  if (!name || name.length > 80) problems.push("name (1–80 chars) is required");
  if (!archetype || archetype.length > 60)
    problems.push("archetype (1–60 chars) is required");
  if (bio.length > 300) problems.push("bio must be ≤ 300 chars");
  if (!worldview || worldview.length > 2000)
    problems.push("worldview (1–2000 chars) is required");
  if (!speechStyle || speechStyle.length > 2000)
    problems.push("speechStyle (1–2000 chars) is required");
  if (!CURATED_VOICE_IDS.has(voiceID))
    problems.push("voiceID must be one of the curated aura-2 voices");
  if (!/^#[0-9a-f]{6}$/.test(tintHex))
    problems.push("tintHex must be a #rrggbb color");
  if (!BASE_BODY_IDS.has(baseBody)) problems.push("baseBody is invalid");
  if (!portraitDataURL && !appearance)
    problems.push("either portraitDataURL or appearance is required");
  if (problems.length > 0) {
    return NextResponse.json({ error: problems.join("; ") }, { status: 400 });
  }

  // Unique id: slug + random suffix; never collides with built-ins.
  let id = `${slugify(name)}-${Math.random().toString(36).slice(2, 8)}`;
  if (BUILT_IN_CHARACTERS.some((c) => c.id === id)) id = `${id}-x`;

  try {
    let bytes: Buffer;
    let contentType: string;
    if (portraitDataURL) {
      const match = /^data:(image\/(?:png|jpeg|webp));base64,(.+)$/.exec(
        portraitDataURL
      );
      if (!match) {
        return NextResponse.json(
          { error: "portraitDataURL must be a base64 png/jpeg/webp data URL" },
          { status: 400 }
        );
      }
      contentType = match[1];
      bytes = Buffer.from(match[2], "base64");
      if (bytes.length === 0 || bytes.length > 8 * 1024 * 1024) {
        return NextResponse.json(
          { error: "portraitDataURL is empty or over 8 MB" },
          { status: 400 }
        );
      }
    } else {
      const generated = await generatePortrait(appearance);
      bytes = generated.bytes;
      contentType = generated.contentType;
    }

    const portraitURL = await uploadPortrait(id, bytes, contentType);

    const def: CharacterDef = {
      id,
      name,
      archetype,
      bio,
      worldview,
      speechStyle,
      voiceID,
      tintHex,
      baseBody: baseBody as BaseBody,
      portraitURL,
      builtIn: false,
      isModerator: false,
      createdAt: new Date().toISOString(),
    };
    await saveCharacter(def);

    return NextResponse.json(
      { character: def },
      { status: 201, headers: { "Cache-Control": "no-store" } }
    );
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Create failed" },
      { status: 502 }
    );
  }
}
