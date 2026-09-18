import { NextRequest, NextResponse } from "next/server";

// harknessai.com is the teacher-training brand: its root serves the
// HarknessAI landing page (same Next.js app, host-based rewrite). Every
// other path — /table, /characters, the API — behaves identically on
// both domains.
export function middleware(req: NextRequest) {
  const host = req.headers.get("host") ?? "";
  if (host === "harknessai.com" || host === "www.harknessai.com") {
    const url = req.nextUrl.clone();
    url.pathname = "/harkness";
    return NextResponse.rewrite(url);
  }
  return NextResponse.next();
}

export const config = { matcher: ["/"] };
