// /play — the browser-playable HarknessAI tutorial (works on both
// harknessai.com/play and roundtable.spmhresearch.org/play).

import type { Metadata } from "next";
import Game from "./Game";

export const metadata: Metadata = {
  title: "Play HarknessAI — a three-minute Harkness coaching game",
  description:
    "Sit at the head of a simulated Harkness table. Guide five AI students to three realizations about Kate Chopin's “The Story of an Hour” — using only open questions, redirects, and silence.",
  openGraph: {
    title: "Play HarknessAI",
    description:
      "Guide a simulated class to three realizations using only questions and silence — the Vision Pro tutorial, playable in your browser.",
    url: "https://harknessai.com/play",
    siteName: "HarknessAI",
    type: "website",
  },
};

export default function PlayPage() {
  return <Game />;
}
