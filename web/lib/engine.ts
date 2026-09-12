// The client-side conversation engine. Port of the visionOS app's
// ConversationDirector + PlaybackQueue: owns the transcript and the
// interruption epoch; every in-flight request and every queued audio chunk
// carries its captured epoch and discards itself when stale.
//
// The server is stateless — each /api/turn call ships the transcript,
// document summary, facts block, and current page context.

import { chunksFor } from "./chunker";
import { specFor } from "./characters";
import { DirectorTurn, PageContext, TranscriptEntry } from "./types";

export interface Insight {
  title: string;
  speakerName: string;
}

export interface EngineCallbacks {
  onTranscript(entries: TranscriptEntry[]): void;
  onActiveSpeaker(id: string | null): void;
  onSubtitle(sub: { speakerId: string; text: string } | null): void;
  onInsight(insight: Insight): void;
  onError(message: string | null): void;
  onRunningChange(running: boolean): void;
}

interface PreparedTurn {
  turn: DirectorTurn;
  chunks: string[];
  audio: Promise<string | null>[]; // object URLs, null on chunk failure
  entryIndex: number; // index of this turn's transcript entry
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export class DiscussionEngine {
  private epoch = 0;
  private transcript: TranscriptEntry[] = [];
  private running = false;

  summary = "";
  factsBlock: string | null = null;
  private page: PageContext = { number: 1, total: 1, text: "" };

  // Playback bookkeeping for interruption fractions.
  private currentEntryIndex = -1;
  private currentChunks: string[] = [];
  private chunksPlayed = 0;
  private currentAudio: HTMLAudioElement | null = null;
  private releaseAudio: (() => void) | null = null;

  constructor(private cb: EngineCallbacks) {}

  get isRunning() {
    return this.running;
  }

  setPage(page: PageContext) {
    const changed = this.page.number !== page.number;
    this.page = page;
    if (changed && this.running) {
      this.push({
        kind: "note",
        text: `The user just turned the document to page ${page.number} of ${page.total}. React to what's on it.`,
      });
    }
  }

  start() {
    if (this.running) return;
    this.running = true;
    this.cb.onRunningChange(true);
    this.cb.onError(null);
    this.epoch += 1;
    void this.runLoop(
      "Open the seminar: the moderator welcomes the table in one warm line and frames the document the group is examining tonight — then hands off with a pointed question.",
      false
    );
  }

  stop() {
    this.running = false;
    this.epoch += 1;
    this.haltAudio();
    this.currentEntryIndex = -1;
    this.cb.onActiveSpeaker(null);
    this.cb.onSubtitle(null);
    this.cb.onRunningChange(false);
  }

  /** The user spoke: invalidate everything in flight, patch the transcript,
   *  and answer with the low-latency model. */
  interject(text: string) {
    const spoken = text.trim();
    if (!spoken) return;
    this.epoch += 1;
    this.haltAudio();
    this.reconcileInterruption();
    this.push({ kind: "user", text: spoken });
    this.running = true;
    this.cb.onRunningChange(true);
    void this.runLoop(
      "The user just spoke. The most fitting character responds to their point directly, addressing them as 'you'.",
      true
    );
  }

  // MARK: - Loop

  private async runLoop(firstDirective: string, fast: boolean) {
    const epoch = this.epoch;
    let pending = this.prepare(firstDirective, fast, epoch);
    while (this.running && this.epoch === epoch) {
      const prepared = await pending;
      if (!prepared || this.epoch !== epoch || !this.running) return;
      // One-turn lookahead: request the next turn while this one plays.
      pending = this.prepare("Continue the discussion naturally.", false, epoch);
      await this.playTurn(prepared, epoch);
      if (this.epoch !== epoch || !this.running) return;
      await sleep(400); // small beat between speakers
    }
  }

  private async prepare(
    directive: string,
    fast: boolean,
    epoch: number
  ): Promise<PreparedTurn | null> {
    try {
      const res = await fetch("/api/turn", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          transcript: this.transcript,
          summary: this.summary,
          factsBlock: this.factsBlock,
          currentPage: this.page,
          directive,
          fast,
        }),
      });
      if (!res.ok) {
        const err = (await res.json().catch(() => null)) as {
          error?: string;
        } | null;
        throw new Error(err?.error ?? `Turn request failed (${res.status})`);
      }
      const turn = (await res.json()) as DirectorTurn;
      if (this.epoch !== epoch) return null;

      const spec = specFor(turn.speaker);
      const entryIndex = this.transcript.length;
      this.push({
        kind: "character",
        id: turn.speaker,
        name: spec?.name ?? turn.speaker,
        text: turn.text,
        interrupted: false,
      });
      if (turn.insight) {
        this.cb.onInsight({
          title: turn.insight,
          speakerName: spec?.name ?? turn.speaker,
        });
      }

      const chunks = chunksFor(turn.text);
      const voiceID = spec?.voiceID ?? "aura-2-hera-en";
      const audio = chunks.map((chunk) => this.fetchTTS(chunk, voiceID));
      return { turn, chunks, audio, entryIndex };
    } catch (err) {
      if (this.epoch === epoch) {
        this.cb.onError(
          err instanceof Error ? err.message : "Turn generation failed"
        );
        this.running = false;
        this.cb.onRunningChange(false);
      }
      return null;
    }
  }

  private async fetchTTS(text: string, voiceID: string): Promise<string | null> {
    try {
      const res = await fetch("/api/tts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text, voiceID }),
      });
      if (!res.ok) return null;
      const blob = await res.blob();
      return URL.createObjectURL(blob);
    } catch {
      return null;
    }
  }

  // MARK: - Playback

  private async playTurn(prepared: PreparedTurn, epoch: number) {
    this.currentEntryIndex = prepared.entryIndex;
    this.currentChunks = prepared.chunks;
    this.chunksPlayed = 0;
    this.cb.onActiveSpeaker(prepared.turn.speaker);
    this.cb.onSubtitle({
      speakerId: prepared.turn.speaker,
      text: prepared.turn.text,
    });

    for (let i = 0; i < prepared.audio.length; i++) {
      const url = await prepared.audio[i];
      if (this.epoch !== epoch) return;
      if (url) {
        await this.playUrl(url);
        URL.revokeObjectURL(url);
      }
      if (this.epoch !== epoch) return;
      this.chunksPlayed = i + 1;
    }
    this.currentEntryIndex = -1;
    this.cb.onActiveSpeaker(null);
  }

  private playUrl(url: string): Promise<void> {
    return new Promise((resolve) => {
      const audio = new Audio(url);
      this.currentAudio = audio;
      let done = false;
      const finish = () => {
        if (done) return;
        done = true;
        this.currentAudio = null;
        this.releaseAudio = null;
        resolve();
      };
      this.releaseAudio = () => {
        audio.pause();
        finish();
      };
      audio.addEventListener("ended", finish);
      audio.addEventListener("error", finish);
      audio.play().catch(finish);
    });
  }

  private haltAudio() {
    this.releaseAudio?.();
  }

  /** After an interruption: drop lookahead turns that were never spoken and
   *  truncate the interrupted line to roughly what was actually heard. */
  private reconcileInterruption() {
    if (this.currentEntryIndex >= 0) {
      // Remove any lookahead entries appended after the currently playing turn.
      if (this.transcript.length > this.currentEntryIndex + 1) {
        this.transcript = this.transcript.slice(0, this.currentEntryIndex + 1);
      }
      const entry = this.transcript[this.currentEntryIndex];
      if (entry?.kind === "character") {
        const spokenText = this.currentChunks
          .slice(0, this.chunksPlayed)
          .join(" ");
        const cutoff = Math.max(8, spokenText.length);
        this.transcript[this.currentEntryIndex] = {
          ...entry,
          text: entry.text.slice(0, cutoff),
          interrupted: cutoff < entry.text.length,
        };
      }
      this.currentEntryIndex = -1;
      this.cb.onTranscript([...this.transcript]);
    } else {
      // Nothing playing: drop any fully-unspoken trailing lookahead turn is
      // not distinguishable here; keep transcript as-is.
    }
    this.cb.onActiveSpeaker(null);
    this.cb.onSubtitle(null);
  }

  private push(entry: TranscriptEntry) {
    this.transcript.push(entry);
    this.cb.onTranscript([...this.transcript]);
  }
}
