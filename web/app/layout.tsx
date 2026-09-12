import type { Metadata, Viewport } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "The Roundtable — an AI seminar on your deck",
  description:
    "Upload an investment deck and listen as five sharp, skeptical-but-curious minds discuss it around an antique seminar table. Speak up any time.",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        {/* Small fixed nav (workstream A) — the main page header lives in
            app/page.tsx and is owned by another workstream. */}
        <nav className="site-nav" aria-label="Site">
          <Link href="/">The Roundtable</Link>
          <Link href="/table">The Table</Link>
          <Link href="/characters">Characters</Link>
        </nav>
        {children}
      </body>
    </html>
  );
}
