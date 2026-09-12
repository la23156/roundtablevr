// DELETE /api/characters/[id] — remove a custom character (built-ins are
// immutable). Also deletes the character's portrait blob.

import { NextRequest, NextResponse } from "next/server";
import { BUILT_IN_CHARACTERS } from "@/lib/characterTypes";
import { deleteCharacter } from "@/lib/characterStore";

export const maxDuration = 30;

export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  if (BUILT_IN_CHARACTERS.some((c) => c.id === id)) {
    return NextResponse.json(
      { error: "Built-in characters cannot be deleted" },
      { status: 403 }
    );
  }
  try {
    const removed = await deleteCharacter(id);
    if (!removed) {
      return NextResponse.json(
        { error: "Character not found" },
        { status: 404 }
      );
    }
    return NextResponse.json(
      { ok: true },
      { headers: { "Cache-Control": "no-store" } }
    );
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Delete failed" },
      { status: 502 }
    );
  }
}
