// The client-side conversation engine. Port of the visionOS app's
// ConversationDirector + PlaybackQueue: owns the transcript and the
// interruption epoch; every in-flight request and every queued audio chunk
// carries its captured epoch and discards itself when stale.
//
// The server is stateless — each /api/turn call ships the transcript,
// document summary, facts block, and current page context.

import { chunksFor } from "./chunker";
import { specFor } from "./characters";
import { Direction, DirectorTurn, PageContext, TranscriptEntry } from "./types";

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
  /** Directed mode: full list of covered key-point indexes (fires as each
   *  covering turn starts playing, and after interruption rollbacks). */
  onCoveredPoints(points: number[]): void;
  /** Directed mode: a moderator check-in turn toward the user is playing. */
  onCheckIn(active: boolean): void;
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

  // ---- Directed mode (workstream C) state ----
  private direction: Direction | null = null;
  /** Which transcript entry covered which key point — entry indexes let an
   *  interruption roll back credit for turns that were never spoken. */
  private coveredMarks: { entryIndex: number; point: number }[] = [];
  private turnsSinceProgress = 0;
  private lastOnTrack = true;
  private pointsSinceCheckIn = 0;
  private pendingCheckIn: number | null = null; // key point awaiting a moderator check-in

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

  /** All key-point indexes credited so far (including lookahead turns). */
  get coveredPoints(): number[] {
    return this.coveredMarks.map((m) => m.point);
  }

  /** Set (or clear) the direction for directed mode. Progress resets only
   *  when the direction actually changes. */
  setDirection(direction: Direction | null) {
    const changed =
      JSON.stringify(direction) !== JSON.stringify(this.direction);
    this.direction = direction;
    if (changed) {
      this.coveredMarks = [];
      this.turnsSinceProgress = 0;
      this.lastOnTrack = true;
      this.pointsSinceCheckIn = 0;
      this.pendingCheckIn = null;
      this.cb.onCoveredPoints([]);
    }
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
    const opening = this.direction
      ? `Open the seminar: the moderator welcomes the table in one warm line and frames tonight's DIRECTED session in her own words — the group is examining the document with a specific goal ("${this.direction.goal}") — then hands off with a pointed question aimed at the first key point.`
      : "Open the seminar: the moderator welcomes the table in one warm line and frames the document the group is examining tonight — then hands off with a pointed question.";
    void this.runLoop(opening, false);
  }

  stop() {
    this.running = false;
    this.epoch += 1;
    this.haltAudio();
    this.currentEntryIndex = -1;
    this.cb.onActiveSpeaker(null);
    this.cb.onSubtitle(null);
    this.cb.onCheckIn(false);
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
      pending = this.prepare(this.continueDirective(), false, epoch);
      await this.playTurn(prepared, epoch);
      if (this.epoch !== epoch || !this.running) return;
      await sleep(400); // small beat between speakers
    }
  }

  /** Directive for the next lookahead turn. In directed mode this is where
   *  check-ins and steering get injected by the client. */
  private continueDirective(): string {
    const dir = this.direction;
    if (!dir) return "Continue the discussion naturally.";

    // 1. A key point just landed and the cadence says: check in with the user.
    if (this.pendingCheckIn !== null) {
      const idx = this.pendingCheckIn;
      this.pendingCheckIn = null;
      return `Key point index ${idx} ("${dir.keyPoints[idx]}") was just covered. The MODERATOR now takes this turn, faces the USER (look_target "user", invites_user true), and conversationally checks the user's understanding of that specific point.`;
    }

    const covered = new Set(this.coveredPoints);
    const nextIdx = dir.keyPoints.findIndex((_, i) => !covered.has(i));
    if (nextIdx < 0) {
      return "All key points are covered. Continue naturally; the moderator may begin drawing the session toward a synthesis of the goal.";
    }

    // 2. Steering: stalled progress or the last turn reported drift.
    if (this.turnsSinceProgress >= 3 || !this.lastOnTrack) {
      // Reset the local triggers so we don't steer every single turn.
      this.turnsSinceProgress = 0;
      this.lastOnTrack = true;
      return dir.strictness === "firm"
        ? `STEERING DIRECTIVE: the discussion has drifted. The moderator politely but firmly cuts in, names the digression in a phrase, and redirects the table to this key point: "${dir.keyPoints[nextIdx]}".`
        : `STEERING DIRECTIVE: the moderator gracefully bridges what was just said back toward the goal ("${dir.goal}"), next point: "${dir.keyPoints[nextIdx]}".`;
    }

    return "Continue the discussion naturally.";
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
          // Directed-mode state rides along on every request (null/absent
          // keeps the API on its classic path).
          direction: this.direction,
          coveredPoints: this.coveredPoints,
          turnsSinceProgress: this.turnsSinceProgress,
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
      this.recordDirectedSignals(turn, entryIndex);
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

  /** Directed-mode bookkeeping at fetch time, so the lookahead request that
   *  fires next already carries accurate coveredPoints/turnsSinceProgress. */
  private recordDirectedSignals(turn: DirectorTurn, entryIndex: number) {
    const dir = this.direction;
    if (!dir) return;
    const cp = turn.covered_point;
    const covered = new Set(this.coveredPoints);
    if (
      typeof cp === "number" &&
      Number.isInteger(cp) &&
      cp >= 0 &&
      cp < dir.keyPoints.length &&
      !covered.has(cp)
    ) {
      this.coveredMarks.push({ entryIndex, point: cp });
      this.turnsSinceProgress = 0;
      this.pointsSinceCheckIn += 1;
      const cadence = dir.checkInStyle === "perPoint" ? 1 : 2;
      if (this.pointsSinceCheckIn >= cadence) {
        this.pendingCheckIn = cp;
        this.pointsSinceCheckIn = 0;
      }
    } else {
      this.turnsSinceProgress += 1;
    }
    this.lastOnTrack = turn.on_track ?? true;
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

    // Directed mode: surface progress/check-in as the turn STARTS playing so
    // the UI stays in sync with what's actually being heard.
    if (this.direction) {
      this.cb.onCoveredPoints(
        this.coveredMarks
          .filter((m) => m.entryIndex <= prepared.entryIndex)
          .map((m) => m.point)
      );
      const isModerator = specFor(prepared.turn.speaker)?.isModerator ?? false;
      this.cb.onCheckIn(isModerator && prepared.turn.invites_user);
    }

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
    this.cb.onCheckIn(false);
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
    // Directed mode: a pending check-in is moot once the user jumps in.
    this.pendingCheckIn = null;
    if (this.currentEntryIndex >= 0) {
      // Remove any lookahead entries appended after the currently playing turn.
      if (this.transcript.length > this.currentEntryIndex + 1) {
        this.transcript = this.transcript.slice(0, this.currentEntryIndex + 1);
      }
      // Roll back key-point credit earned by lookahead turns that were dropped.
      if (
        this.coveredMarks.some((m) => m.entryIndex > this.currentEntryIndex)
      ) {
        this.coveredMarks = this.coveredMarks.filter(
          (m) => m.entryIndex <= this.currentEntryIndex
        );
        if (this.direction) this.cb.onCoveredPoints(this.coveredPoints);
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
    this.cb.onCheckIn(false);
  }

  private push(entry: TranscriptEntry) {
    this.transcript.push(entry);
    this.cb.onTranscript([...this.transcript]);
  }
}
