// Ported from roundtable/Session/TurnSynthesizer.swift (chunks(for:)).
//
// Deepgram generates audio at roughly 2x realtime, so waiting for a whole turn
// costs seconds. Split the text into speakable chunks: sentences, but the FIRST
// chunk is capped at ~90 chars (broken at a clause boundary) so time-to-first-
// audio stays low; later chunks are whole sentences (fewer prosody seams).

export function chunksFor(text: string): string[] {
  const sentences: string[] = [];
  let current = "";
  for (const ch of text) {
    current += ch;
    if (".!?…".includes(ch) && current.trim().length > 2) {
      sentences.push(current.trim());
      current = "";
    }
  }
  const tail = current.trim();
  if (tail.length > 0) sentences.push(tail);
  if (sentences.length === 0) return [];

  // Cap the opening chunk at a clause boundary for fast first audio.
  const first = sentences[0];
  if (first.length > 90) {
    const candidates = [",", ";", "—", ":"];
    const window = first.slice(0, 110);
    let cut = -1;
    for (let i = window.length - 1; i >= 0; i--) {
      if (candidates.includes(window[i])) {
        cut = i;
        break;
      }
    }
    if (cut > 25) {
      const head = first.slice(0, cut + 1);
      const rest = first.slice(cut + 1).trim();
      sentences[0] = head;
      if (rest.length > 0) sentences.splice(1, 0, rest);
    }
  }
  return sentences;
}
