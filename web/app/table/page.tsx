"use client";

// Roundtable — an AI seminar table that discusses an uploaded investment deck.

import { useCallback, useEffect, useRef, useState } from "react";
import PdfViewer, { ExtractedDoc } from "@/components/PdfViewer";
import CardTable from "@/components/CardTable";
import TranscriptLog from "@/components/TranscriptLog";
import DirectedPanel, {
  EMPTY_DIRECTION,
  isDirectionValid,
} from "@/components/DirectedPanel";
import { DiscussionEngine, Insight } from "@/lib/engine";
import { MicController } from "@/lib/mic";
import { specFor } from "@/lib/characters";
import { BUILT_IN_CHARACTERS, type CharacterDef } from "@/lib/characterTypes";
import { MIN_SEATED } from "@/lib/rosterState";
import { Direction, TranscriptEntry } from "@/lib/types";

type DocPhase = "none" | "extracting" | "summarizing" | "ready";

export default function Home() {
  const [file, setFile] = useState<File | null>(null);
  const [doc, setDoc] = useState<ExtractedDoc | null>(null);
  const [docPhase, setDocPhase] = useState<DocPhase>("none");
  const [summary, setSummary] = useState<string>("");
  const [factsReady, setFactsReady] = useState(false);

  const [transcript, setTranscript] = useState<TranscriptEntry[]>([]);
  const [activeSpeaker, setActiveSpeaker] = useState<string | null>(null);
  const [subtitle, setSubtitle] = useState<{
    speakerId: string;
    text: string;
  } | null>(null);
  const [insights, setInsights] = useState<Insight[]>([]);
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Card roster (workstream B): seated cast + full fetched roster.
  const [seatedCast, setSeatedCast] = useState<CharacterDef[]>([]);
  const [roster, setRoster] = useState<CharacterDef[]>(BUILT_IN_CHARACTERS);

  // Directed mode (workstream C).
  const [directedEnabled, setDirectedEnabled] = useState(false);
  const [direction, setDirection] = useState<Direction>(EMPTY_DIRECTION);
  const [covered, setCovered] = useState<number[]>([]);
  const [checkIn, setCheckIn] = useState(false);

  const [micOn, setMicOn] = useState(false);
  const [micState, setMicState] = useState<
    "idle" | "listening" | "speech" | "processing"
  >("idle");
  const [micLevel, setMicLevel] = useState(0);
  const [interim, setInterim] = useState<string | null>(null);

  const engineRef = useRef<DiscussionEngine | null>(null);
  const micRef = useRef<MicController | null>(null);
  const docRef = useRef<ExtractedDoc | null>(null);

  // Engine singleton.
  if (engineRef.current === null && typeof window !== "undefined") {
    engineRef.current = new DiscussionEngine({
      onTranscript: setTranscript,
      onActiveSpeaker: setActiveSpeaker,
      onSubtitle: setSubtitle,
      onInsight: (insight) => setInsights((prev) => [...prev, insight]),
      onError: setError,
      onRunningChange: setRunning,
      onCoveredPoints: setCovered,
      onCheckIn: setCheckIn,
    });
  }

  // The seated card set IS the session cast: castIds ride on every /api/turn
  // request, and voice/name lookups resolve custom characters too.
  const handleCastChange = useCallback(
    (seated: CharacterDef[], all: CharacterDef[]) => {
      setSeatedCast(seated);
      setRoster(all);
      engineRef.current?.setCast(seated);
    },
    []
  );

  // Keep the engine's direction in sync: a valid, enabled direction rides on
  // every /api/turn request; otherwise the classic mode is untouched.
  const directedValid = isDirectionValid(direction);
  useEffect(() => {
    engineRef.current?.setDirection(
      directedEnabled && directedValid ? direction : null
    );
  }, [directedEnabled, directedValid, direction]);

  const handleFile = useCallback((f: File | null) => {
    if (!f) return;
    engineRef.current?.stop();
    setTranscript([]);
    setInsights([]);
    setSubtitle(null);
    setSummary("");
    setFactsReady(false);
    setCovered([]);
    setCheckIn(false);
    setError(null);
    setDoc(null);
    docRef.current = null;
    setFile(f);
    setDocPhase("extracting");
  }, []);

  const handleExtracted = useCallback(async (extracted: ExtractedDoc) => {
    setDoc(extracted);
    docRef.current = extracted;
    const engine = engineRef.current;
    engine?.setPage({
      number: 1,
      total: extracted.pageCount,
      text: extracted.pageTexts[0] ?? "",
    });

    setDocPhase("summarizing");
    try {
      const res = await fetch("/api/summarize", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: extracted.fullText }),
      });
      if (!res.ok) throw new Error("Summarize failed");
      const { summary, entities } = (await res.json()) as {
        summary: string;
        entities: string[];
      };
      setSummary(summary);
      if (engine) engine.summary = summary;
      setDocPhase("ready");

      // Fresh facts are a bonus, never a blocker.
      try {
        const factsRes = await fetch("/api/facts", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ entities }),
        });
        const { factsBlock } = (await factsRes.json()) as {
          factsBlock: string | null;
        };
        if (engine && factsBlock) {
          engine.factsBlock = factsBlock;
          setFactsReady(true);
        }
      } catch {
        // ignore
      }
    } catch {
      setError("Couldn't summarize the document — the discussion can still start.");
      setDocPhase("ready");
    }
  }, []);

  const handlePageChange = useCallback((pageNumber: number) => {
    const extracted = docRef.current;
    if (!extracted) return;
    engineRef.current?.setPage({
      number: pageNumber,
      total: extracted.pageCount,
      text: extracted.pageTexts[pageNumber - 1] ?? "",
    });
  }, []);

  const toggleMic = useCallback(async () => {
    if (micRef.current?.isActive) {
      micRef.current.stop();
      setMicOn(false);
      return;
    }
    const mic = new MicController({
      onLevel: setMicLevel,
      onInterim: setInterim,
      onFinal: (text) => engineRef.current?.interject(text),
      onState: setMicState,
    });
    micRef.current = mic;
    try {
      await mic.start();
      setMicOn(true);
    } catch {
      setError("Microphone access was denied.");
      setMicOn(false);
    }
  }, []);

  useEffect(() => {
    return () => {
      micRef.current?.stop();
      engineRef.current?.stop();
    };
  }, []);

  // Resolve speaker display info from the fetched roster (customs included),
  // falling back to the static built-in specs.
  const subtitleDef = subtitle
    ? roster.find((c) => c.id === subtitle.speakerId)
    : undefined;
  const subtitleFallback = subtitle ? specFor(subtitle.speakerId) : undefined;
  const subtitleTint = subtitleDef?.tintHex ?? subtitleFallback?.tint ?? null;
  const subtitleName =
    subtitleDef?.name ?? subtitleFallback?.name ?? subtitle?.speakerId ?? "";
  const rosterReady = seatedCast.length >= MIN_SEATED;
  const canStart =
    docPhase === "ready" &&
    !running &&
    rosterReady &&
    (!directedEnabled || directedValid);
  const directedSessionStarted =
    directedEnabled &&
    transcript.some((entry) => entry.kind === "character");

  return (
    <main className="shell">
      <header className="masthead">
        <h1>The Roundtable</h1>
        <p className="tagline">
          Five minds, one table, and the deck you brought with you.
        </p>
      </header>

      <div className="columns">
        <section className="pdf-pane">
          <div className="pane-heading">
            <h2>The Document</h2>
            <label className="btn btn-upload">
              {file ? "Replace PDF" : "Upload PDF"}
              <input
                type="file"
                accept="application/pdf"
                hidden
                onChange={(e) => handleFile(e.target.files?.[0] ?? null)}
              />
            </label>
          </div>
          <PdfViewer
            file={file}
            onExtracted={handleExtracted}
            onPageChange={handlePageChange}
          />
          {docPhase === "summarizing" && (
            <div className="doc-status">Briefing the table on your document…</div>
          )}
          {docPhase === "ready" && summary && (
            <div className="doc-status ok">
              Briefing ready{factsReady ? " · fresh context gathered" : ""}.
            </div>
          )}
        </section>

        <section className="salon-pane">
          <CardTable
            activeSpeaker={activeSpeaker}
            onCastChange={handleCastChange}
          />

          <div
            className={`subtitle-area${checkIn ? " checkin-pulse" : ""}`}
            style={
              subtitleTint ? { borderColor: `${subtitleTint}66` } : undefined
            }
          >
            {subtitle ? (
              <>
                <div
                  className="subtitle-speaker"
                  style={subtitleTint ? { color: subtitleTint } : undefined}
                >
                  {subtitleName}
                </div>
                <div className="subtitle-text">{subtitle.text}</div>
              </>
            ) : (
              <div className="subtitle-idle">
                {running ? "…" : "The floor is open."}
              </div>
            )}
          </div>

          <DirectedPanel
            enabled={directedEnabled}
            onEnabledChange={setDirectedEnabled}
            direction={direction}
            onDirectionChange={setDirection}
            covered={covered}
            running={running}
            sessionStarted={directedSessionStarted}
          />

          <TranscriptLog
            entries={transcript}
            tintFor={(id) => roster.find((c) => c.id === id)?.tintHex}
          />

          {insights.length > 0 && (
            <div className="insights">
              {insights.slice(-3).map((ins, i) => (
                <span key={i} className="insight-chip">
                  ✦ {ins.title}
                </span>
              ))}
            </div>
          )}

          {(interim || micState === "processing") && (
            <div className="interim">
              {interim ?? "Transcribing what you said…"}
            </div>
          )}

          {error && <div className="error-banner">{error}</div>}

          {checkIn && (
            <div className="checkin-hint">
              The table turns to <strong>YOU</strong> — press the mic and share
              your read.
            </div>
          )}

          <div className="controls">
            {!running ? (
              <button
                className="btn btn-primary"
                disabled={!canStart}
                onClick={() => engineRef.current?.start()}
              >
                {transcript.length > 0 ? "Resume discussion" : "Start discussion"}
              </button>
            ) : (
              <button
                className="btn btn-secondary"
                onClick={() => engineRef.current?.stop()}
              >
                Pause discussion
              </button>
            )}

            <button
              className={`btn btn-mic${micOn ? " live" : ""}`}
              onClick={toggleMic}
              title={
                micOn
                  ? "Stop listening"
                  : "Listen for your voice — speak to join the table"
              }
            >
              <span
                className="mic-level"
                style={{ transform: `scaleY(${0.15 + micLevel * 0.85})` }}
              />
              {micOn
                ? micState === "speech"
                  ? "Hearing you…"
                  : micState === "processing"
                    ? "Thinking…"
                    : "Listening"
                : "Join by voice"}
            </button>
          </div>

          {docPhase === "ready" && !running && !rosterReady && (
            <p className="hint">
              Seat at least {MIN_SEATED} characters (the moderator is already
              at the table) to start the discussion.
            </p>
          )}

          {docPhase === "none" && (
            <p className="hint">
              Upload an investment deck, let the table read it, then start the
              discussion. Turn pages any time — they&apos;ll notice.
            </p>
          )}
        </section>
      </div>
    </main>
  );
}
