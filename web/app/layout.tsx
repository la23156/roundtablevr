import type { Metadata, Viewport } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://roundtable.spmhresearch.org"),
  title: "The Roundtable — an AI seminar on your deck",
  description:
    "Upload an investment deck and listen as five sharp, skeptical-but-curious minds discuss it around an antique seminar table. Speak up any time.",
  openGraph: {
    title: "The Roundtable",
    description:
      "A seminar table of AI minds — on Apple Vision Pro and the web. Pick a question or upload a deck, listen in, and speak up any time.",
    url: "https://roundtable.spmhresearch.org",
    siteName: "The Roundtable",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "The Roundtable",
    description:
      "A seminar table of AI minds — on Apple Vision Pro and the web.",
  },
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
