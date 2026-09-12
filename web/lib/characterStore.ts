// Character store — SERVER-SIDE ONLY. Custom characters persist in the
// Vercel Blob store `roundtable-characters`: an index at `characters.json`
// plus one portrait per character at `portraits/<id>.png`. Last-write-wins
// on the index is acceptable for this app.

import { del, list, put } from "@vercel/blob";
import {
  BUILT_IN_CHARACTERS,
  type CharacterDef,
} from "@/lib/characterTypes";

const INDEX_PATH = "characters.json";
// Overwritten blobs (characters.json) can serve STALE content for up to ~60s
// at the Blob origin (observed: `age: 49` on a cache MISS), which breaks
// read-after-write for create/delete. So the authoritative index is written
// to a fresh, timestamped pathname on every write (a never-before-seen URL is
// never stale), found via list(), and `characters.json` is kept as a mirror.
const VERSIONED_PREFIX = "index/characters-";

async function readCustomIndex(): Promise<CharacterDef[]> {
  const { blobs } = await list({ prefix: VERSIONED_PREFIX });
  if (blobs.length === 0) return [];
  // Date.now() is fixed-width until the year 2286 — lexical sort works.
  const newest = blobs.reduce((a, b) => (b.pathname > a.pathname ? b : a));
  const res = await fetch(newest.url, { cache: "no-store" });
  if (!res.ok) throw new Error(`Blob index fetch failed: HTTP ${res.status}`);
  const parsed = (await res.json()) as unknown;
  return Array.isArray(parsed) ? (parsed as CharacterDef[]) : [];
}

async function writeCustomIndex(defs: CharacterDef[]): Promise<void> {
  const json = JSON.stringify(defs, null, 2);
  await put(`${VERSIONED_PREFIX}${Date.now()}.json`, json, {
    access: "public",
    contentType: "application/json",
    addRandomSuffix: false,
    cacheControlMaxAge: 0, // clamped to 60s by Vercel
  });
  // Best-effort: mirror to the stable path and prune superseded versions.
  try {
    await put(INDEX_PATH, json, {
      access: "public",
      contentType: "application/json",
      allowOverwrite: true,
      addRandomSuffix: false,
      cacheControlMaxAge: 0,
    });
    const { blobs } = await list({ prefix: VERSIONED_PREFIX });
    const sorted = [...blobs].sort((a, b) =>
      a.pathname < b.pathname ? 1 : -1
    );
    const stale = sorted.slice(3).map((b) => b.url); // keep newest 3
    if (stale.length > 0) await del(stale);
  } catch {
    // Mirror/prune failures never fail the write itself.
  }
}

/** Built-in five + all custom characters (customs newest-last). */
export async function getAllCharacters(): Promise<CharacterDef[]> {
  const customs = await readCustomIndex();
  return [...BUILT_IN_CHARACTERS, ...customs];
}

/** Upload a confirmed portrait; returns its public Blob URL. */
export async function uploadPortrait(
  id: string,
  bytes: Buffer,
  contentType = "image/png"
): Promise<string> {
  const blob = await put(`portraits/${id}.png`, bytes, {
    access: "public",
    contentType,
    allowOverwrite: true,
    addRandomSuffix: false,
  });
  return blob.url;
}

/** Persist a new custom character into the index. */
export async function saveCharacter(def: CharacterDef): Promise<void> {
  const customs = await readCustomIndex();
  const next = customs.filter((c) => c.id !== def.id);
  next.push(def);
  await writeCustomIndex(next);
}

/** Delete a custom character (and its portrait blob). Returns false when the
 *  id is unknown or refers to a built-in. */
export async function deleteCharacter(id: string): Promise<boolean> {
  if (BUILT_IN_CHARACTERS.some((c) => c.id === id)) return false;
  const customs = await readCustomIndex();
  const target = customs.find((c) => c.id === id);
  if (!target) return false;
  await writeCustomIndex(customs.filter((c) => c.id !== id));
  if (target.portraitURL.startsWith("https://")) {
    try {
      await del(target.portraitURL);
    } catch {
      // Orphaned portrait blobs are harmless; the index removal is what counts.
    }
  }
  return true;
}
