import type { Metadata, Viewport } from "next";
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
      <body>{children}</body>
    </html>
  );
}
