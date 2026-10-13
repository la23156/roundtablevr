"use client";

// The playable 2D HarknessAI tutorial: the Vision Pro conversation-guide
// game ported to the browser. The player is the teacher at the near edge
// of the table; every advance is gated on a line they actually send.

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import {
  GuideGate, STUDENTS, NARRATOR_VOICE, NODES, SCORE, PAGES, TURNS, TUTOR,
  LECTURE_WORDS, launchGate, windowGate, deflectGate, bodyGate, plantGate,
} from "./script";

// Seat positions, in percent of the stage (students along the far arc,
// the teacher at the near edge — "you are sitting at the table").
const SEATS: Record<string, { x: number; y: number }> = {
  wren: { x: 15, y: 30 },
  maddie: { x: 32, y: 16 },
  jayden: { x: 50, y: 11 },
  tyler: { x: 68, y: 16 },
  june: { x: 85, y: 30 },
  teacher: { x: 50, y: 88 },
};

type NoteState = "idle" | "flash" | "pulse" | "hit";
type Phase = "title" | "playing" | "debrief";
type GateKind = "launch" | "normal" | "deflect";

interface Edge { x1: number; y1: number; x2: number; y2: number; teacher: boolean; id: number }
interface Bubble { speaker: string; text: string; shown: number }
interface GameEvent { label: string; pts: number }

const wordCount = (s: string) => s.trim().split(/\s+/).filter(Boolean).length;

export default function Game() {
  const [phase, setPhase] = useState<Phase>("title");
  const [score, setScore] = useState(0);
  const [pageIdx, setPageIdx] = useState(0);
  const [notes, setNotes] = useState<NoteState[]>(["idle", "idle", "idle"]);
  const [bubble, setBubble] = useState<Bubble | null>(null);
  const [speaking, setSpeaking] = useState<string | null>(null);
  const [tutorLine, setTutorLine] = useState<string | null>(null);
  const [gate, setGate] = useState<GuideGate | null>(null);
  const [gateKind, setGateKind] = useState<GateKind>("normal");
  const [gateHint, setGateHint] = useState<string | null>(null);
  const [gateShake, setGateShake] = useState(0);
  const [why, setWhy] = useState<string | null>(null);
  const [tension, setTension] = useState<number | null>(null);
  const [edges, setEdges] = useState<Edge[]>([]);
  const [flash, setFlash] = useState<{ text: string; good: boolean; id: number } | null>(null);
  const [input, setInput] = useState("");
  const [events, setEvents] = useState<GameEvent[]>([]);
  const [teacherWords, setTeacherWords] = useState(0);
  const [studentWords, setStudentWords] = useState(0);
  const [voicesOn, setVoicesOn] = useState(true);
  const [listening, setListening] = useState(false);

  const alive = useRef(true);
  const submitResolve = useRef<((line: string) => void) | null>(null);
  const silenceBroken = useRef(false);
  const edgeId = useRef(0);
  const prevSpeaker = useRef<string | null>(null);
  const audioCtx = useRef<AudioContext | null>(null);
  const voicesOnRef = useRef(false);
  voicesOnRef.current = voicesOn;

  useEffect(() => () => { alive.current = false; }, []);

  const sleep = (ms: number) =>
    new Promise<void>((r) => setTimeout(() => r(), ms));

  // ---- Audio: the success chime (E5 → B5, soft sine), WebAudio-generated.
  const chime = useCallback(() => {
    const ctx = audioCtx.current;
    if (!ctx) return;
    [[659.25, 0], [987.77, 0.16]].forEach(([freq, at]) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = "sine";
      osc.frequency.value = freq;
      const t = ctx.currentTime + at;
      gain.gain.setValueAtTime(0.0001, t);
      gain.gain.exponentialRampToValueAtTime(0.18, t + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.7);
      osc.connect(gain).connect(ctx.destination);
      osc.start(t);
      osc.stop(t + 0.8);
    });
  }, []);

  // Spoken voices via the existing Deepgram proxy. Clips play through the
  // AudioContext unlocked by the start tap — `new Audio().play()` outside a
  // gesture is blocked on iOS Safari, decoded buffers are not.
  const speakAloud = useCallback(async (text: string, voiceID: string) => {
    if (!voicesOnRef.current) return;
    try {
      const res = await fetch("/api/tts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text, voiceID }),
      });
      if (!res.ok) return;
      const bytes = await res.arrayBuffer();
      const ctx = audioCtx.current;
      if (ctx) {
        if (ctx.state === "suspended") await ctx.resume();
        const clip = await ctx.decodeAudioData(bytes.slice(0));
        if (!voicesOnRef.current) return;   // muted while fetching
        await new Promise<void>((resolve) => {
          const src = ctx.createBufferSource();
          src.buffer = clip;
          src.connect(ctx.destination);
          src.onended = () => resolve();
          src.start();
          setTimeout(resolve, (clip.duration + 1) * 1000);  // safety net
        });
      } else {
        const url = URL.createObjectURL(new Blob([bytes], { type: "audio/mpeg" }));
        await new Promise<void>((resolve) => {
          const a = new Audio(url);
          a.onended = () => { URL.revokeObjectURL(url); resolve(); };
          a.onerror = () => { URL.revokeObjectURL(url); resolve(); };
          a.play().catch(() => resolve());
        });
      }
    } catch { /* voices are a garnish — never block the game */ }
  }, []);

  const showFlash = useCallback((text: string, good: boolean) => {
    setFlash({ text, good, id: Date.now() });
  }, []);

  const award = useCallback((pts: number, label: string, flashText?: string) => {
    setScore((s) => s + pts);
    setEvents((e) => [...e, { label, pts }]);
    showFlash(flashText ?? `${label} ${pts > 0 ? "+" : ""}${pts}`, pts >= 0);
  }, [showFlash]);

  const addEdge = useCallback((from: string | null, to: string) => {
    if (!from || from === to) { prevSpeaker.current = to; return; }
    const a = SEATS[from]; const b = SEATS[to];
    if (a && b) {
      setEdges((es) => [...es.slice(-11), {
        x1: a.x, y1: a.y, x2: b.x, y2: b.y,
        teacher: from === "teacher" || to === "teacher",
        id: edgeId.current++,
      }]);
    }
    prevSpeaker.current = to;
  }, []);

  // ---- The Tutor speaks (between gates, in the console).
  const tutorSay = useCallback(async (text: string) => {
    if (!alive.current) return;
    setTutorLine(text);
    const voice = speakAloud(text, NARRATOR_VOICE);
    await sleep(Math.max(2000, text.length * 42));
    await voice;
    if (alive.current) setTutorLine(null);
  }, [speakAloud]);

  // ---- A student takes a turn: glow, web edge, typewriter, node effects.
  const studentSay = useCallback(async (turnKey: keyof typeof TURNS) => {
    if (!alive.current) return;
    const turn = TURNS[turnKey];
    setSpeaking(turn.speaker);
    addEdge(prevSpeaker.current, turn.speaker);
    setStudentWords((w) => w + wordCount(turn.text));
    if (turn.closestNode && (turn.closeness ?? 0) >= 0.5) {
      setNotes((n) => n.map((st, i) =>
        i === turn.closestNode! - 1 && st === "idle" ? "pulse" : st));
    }
    const student = STUDENTS.find((s) => s.id === turn.speaker);
    const voice = speakAloud(turn.text, student?.voiceID ?? "");
    for (let i = 0; i <= turn.text.length; i += 2) {
      if (!alive.current) return;
      setBubble({ speaker: turn.speaker, text: turn.text, shown: i });
      await sleep(17);
    }
    setBubble({ speaker: turn.speaker, text: turn.text, shown: turn.text.length });
    await voice;
    await sleep(voicesOnRef.current ? 300 : 1100);
    setSpeaking(null);
    if (turn.coveredNode) {
      setNotes((n) => n.map((st, i) => (i === turn.coveredNode! - 1 ? "hit" : st)));
      award(SCORE.nodeReached, `Realization ${turn.coveredNode} landed`,
        `Realization landed +${SCORE.nodeReached}`);
      await sleep(900);
    }
  }, [addEdge, award, speakAloud]);

  // ---- A gate: the class waits until the teacher sends a matching line.
  const awaitGate = useCallback(async (g: GuideGate, kind: GateKind) => {
    setGate(g); setGateKind(kind); setGateHint(null); setInput("");
    let misses = 0;
    for (;;) {
      const line = await new Promise<string>((resolve) => {
        submitResolve.current = resolve;
        // Quiet too long? The Tutor nudges (cleared when a line arrives).
        setTimeout(() => {
          if (submitResolve.current === resolve) setGateHint(g.nudge);
        }, 25000);
      });
      submitResolve.current = null;
      if (!alive.current) return;
      setTeacherWords((w) => w + wordCount(line));
      const lowered = ` ${line.toLowerCase()} `;

      if (kind === "deflect" && LECTURE_WORDS.some((w) => lowered.includes(w)) &&
          !g.keywords.some((k) => lowered.includes(k))) {
        // Answered the student directly: the Lecturing Penalty.
        award(SCORE.lecturingPenalty, "Lecturing penalty",
          `Lecturing Penalty ${SCORE.lecturingPenalty}`);
        setGateHint(TUTOR.lectured);
        setGateShake(Date.now());
        continue;
      }
      const matched = g.keywords.length === 0
        ? wordCount(line) >= 4
        : g.keywords.some((k) => lowered.includes(k));
      if (matched) {
        addEdge(prevSpeaker.current, "teacher");
        setGate(null); setGateHint(null);
        chime();
        return;
      }
      misses += 1;
      setGateShake(Date.now());
      if (misses % 2 === 0) setGateHint(g.nudge);
    }
  }, [addEdge, award, chime]);

  // ---- The silence: hold out while the tension bar fills (~7 s).
  const silenceChallenge = useCallback(async (): Promise<"held" | "rescued"> => {
    silenceBroken.current = false;
    setTension(0);
    const t0 = Date.now();
    const DURATION = 7000;
    for (;;) {
      await sleep(100);
      if (!alive.current) return "held";
      if (silenceBroken.current) { setTension(null); return "rescued"; }
      const p = (Date.now() - t0) / DURATION;
      if (p >= 1) { setTension(null); return "held"; }
      setTension(p);
    }
  }, []);

  // ---- The whole lesson, in order (the v4 script).
  const run = useCallback(async () => {
    // ACT 0 — the briefing.
    await tutorSay(TUTOR.welcome);
    await tutorSay(TUTOR.intention);
    setNotes(["flash", "idle", "idle"]);
    await tutorSay(TUTOR.brief1);
    setNotes(["idle", "flash", "idle"]);
    await tutorSay(TUTOR.brief2);
    setNotes(["idle", "idle", "flash"]);
    await tutorSay(TUTOR.brief3);
    setNotes(["idle", "idle", "idle"]);
    await tutorSay(TUTOR.rule);

    // ACT 1 — the launch, then the silence.
    await awaitGate(launchGate, "launch");
    setWhy(launchGate.whyItWorks);
    setEvents((e) => [...e, { label: "Catalyst question launched the class", pts: 0 }]);
    await tutorSay(TUTOR.afterLaunch);
    setWhy(null);
    let result = await silenceChallenge();
    if (result === "rescued") {
      award(SCORE.rescue, "Rescued the silence");
      await tutorSay(TUTOR.rescued);
      result = await silenceChallenge();
    }
    if (result === "held") {
      award(SCORE.silenceHeld, "Silence held", `Silence held +${SCORE.silenceHeld} — a student steps up`);
      setWhy("Silence discipline: the discomfort you didn't rescue is exactly what made a student take ownership.");
    } else {
      award(SCORE.rescue, "Rescued the silence again");
    }
    await studentSay("openerJayden");
    setWhy(null);

    // ACT 2 — the window (note 1).
    setPageIdx(1);
    await sleep(1200);
    await studentSay("weatherJayden");
    await awaitGate(windowGate, "normal");
    award(SCORE.goodMove, "Steered to the window", `Good steer +${SCORE.goodMove}`);
    setWhy(windowGate.whyItWorks);
    await studentSay("windowJune");
    await tutorSay(TUTOR.note1);
    setWhy(null);

    // ACT 3 — the deflection, then the body (note 2).
    setPageIdx(2);
    await sleep(1200);
    await studentSay("tylerDeflection");
    await awaitGate(deflectGate, "deflect");
    award(SCORE.deflectionPassed, "Deflection passed", `Deflection passed +${SCORE.deflectionPassed}`);
    setWhy(deflectGate.whyItWorks);
    await studentSay("maddieCircling");
    await awaitGate(bodyGate, "normal");
    award(SCORE.goodMove, "Steered to the body", `Good steer +${SCORE.goodMove}`);
    setWhy(bodyGate.whyItWorks);
    await studentSay("wrenBody");
    await tutorSay(TUTOR.note2);
    setWhy(null);

    // ACT 4 — the plant (note 3).
    setPageIdx(3);
    await sleep(1200);
    await studentSay("endingJayden");
    await awaitGate(plantGate, "normal");
    award(SCORE.goodMove, "Steered to the first line", `Good steer +${SCORE.goodMove}`);
    setWhy(plantGate.whyItWorks);
    await studentSay("plantJune");
    chime();
    await tutorSay(TUTOR.outro);
    if (alive.current) setPhase("debrief");
  }, [tutorSay, awaitGate, silenceChallenge, studentSay, award, chime]);

  const started = useRef(false);
  const start = useCallback(() => {
    if (started.current) return;   // a double-click must not start two runs
    started.current = true;
    try {
      type Win = Window & { webkitAudioContext?: typeof AudioContext };
      const Ctor = window.AudioContext ?? (window as Win).webkitAudioContext;
      if (Ctor && !audioCtx.current) audioCtx.current = new Ctor();
      audioCtx.current?.resume();
    } catch { /* no audio, still playable */ }
    setPhase("playing");
    void run();
  }, [run]);

  const reset = useCallback(() => { window.location.reload(); }, []);

  const onSubmit = useCallback((e: React.FormEvent) => {
    e.preventDefault();
    const line = input.trim();
    if (!line) return;
    setInput("");
    setGateHint(null);
    submitResolve.current?.(line);
  }, [input]);

  // Optional voice input (progressive enhancement, browser-local).
  const micSupported = typeof window !== "undefined" &&
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    Boolean((window as any).SpeechRecognition || (window as any).webkitSpeechRecognition);
  const listen = useCallback(() => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const Ctor = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!Ctor) return;
    const rec = new Ctor();
    rec.lang = "en-US";
    rec.interimResults = false;
    setListening(true);
    rec.onresult = (ev: { results: { [i: number]: { [j: number]: { transcript: string } } } }) => {
      setInput(ev.results[0][0].transcript);
      setListening(false);
    };
    rec.onerror = () => setListening(false);
    rec.onend = () => setListening(false);
    rec.start();
  }, []);

  const talkRatio = teacherWords + studentWords > 0
    ? teacherWords / (teacherWords + studentWords) : 0;

  // ================= Render =================

  if (phase === "debrief") {
    return (
      <Debrief score={score} events={events} talkRatio={talkRatio} onReplay={reset} />
    );
  }

  const bubbleSeat = bubble ? SEATS[bubble.speaker] : null;
  const bubbleStudent = bubble ? STUDENTS.find((s) => s.id === bubble.speaker) : null;

  return (
    <div className="game">
      {/* HUD */}
      <div className="game-hud">
        <span className="game-score">★ {score}</span>
        <span className="game-nodes">
          {notes.map((n, i) => (
            <span key={i} className={`game-node-dot ${n}`} title={NODES[i]} />
          ))}
        </span>
        {tension !== null && (
          <span className="game-hud-tension"><span style={{ width: `${tension * 100}%` }} /></span>
        )}
        <span className="game-talk">you: {Math.round(talkRatio * 100)}%</span>
        <button className="game-sound" title="Student voices on/off"
          onClick={() => setVoicesOn((v) => !v)}>
          {voicesOn ? "🔊" : "🔇"}
        </button>
        {flash && (
          <span key={flash.id} className={`game-flash ${flash.good ? "good" : "bad"}`}>
            {flash.text}
          </span>
        )}
      </div>

      {/* The board (story page) */}
      <div className="game-board">
        <div className="game-board-label">ON THE BOARD — “The Story of an Hour” · {PAGES[pageIdx].label}</div>
        <p>{PAGES[pageIdx].excerpt}</p>
      </div>

      {/* The room */}
      <div className="game-stage">
        <div className="game-table" />

        {/* Conversation web */}
        <svg className="game-web" viewBox="0 0 100 100" preserveAspectRatio="none">
          {edges.map((e, i) => (
            <line key={e.id} x1={e.x1} y1={e.y1} x2={e.x2} y2={e.y2}
              className={e.teacher ? "teacher" : "peer"}
              style={{ opacity: 0.25 + 0.75 * ((i + 1) / edges.length) }} />
          ))}
        </svg>

        {/* Post-it notes */}
        <div className="game-notes">
          {NODES.map((label, i) => (
            <div key={label} className={`game-postit ${notes[i]}`}
              style={{ transform: `rotate(${[-4, 2, -2][i]}deg)` }}>
              <span className="game-postit-num">{i + 1}</span>
              <span className="game-postit-label">{label}</span>
              {notes[i] === "hit" && <span className="game-postit-check">✓ +100</span>}
              {notes[i] === "pulse" && <span className="game-postit-closing">closing in…</span>}
            </div>
          ))}
        </div>

        {/* Students */}
        {STUDENTS.map((s) => (
          <div key={s.id}
            className={`game-seat ${speaking === s.id ? "speaking" : ""}`}
            style={{ left: `${SEATS[s.id].x}%`, top: `${SEATS[s.id].y}%` }}>
            <span className="game-avatar" style={{ background: s.color }}>
              {s.name[0]}
            </span>
            <span className="game-seat-name">{s.name}</span>
            <span className="game-seat-type">{s.archetype}</span>
          </div>
        ))}
        <div className="game-seat teacher"
          style={{ left: `${SEATS.teacher.x}%`, top: `${SEATS.teacher.y}%` }}>
          <span className="game-avatar you">YOU</span>
          <span className="game-seat-name">the teacher</span>
        </div>

        {/* Speech bubble */}
        {bubble && bubbleSeat && (
          <div className="game-bubble"
            style={{
              left: `${Math.min(78, Math.max(22, bubbleSeat.x))}%`,
              borderColor: bubbleStudent?.color,
            }}>
            <span className="game-bubble-name" style={{ color: bubbleStudent?.color }}>
              {bubbleStudent?.name}
            </span>
            {bubble.text.slice(0, bubble.shown)}
            {bubble.shown < bubble.text.length && <span className="game-caret" />}
          </div>
        )}

        {/* Title overlay */}
        {phase === "title" && (
          <div className="game-title-veil">
            <div className="game-title-card">
              <h1>Run the table.</h1>
              <p>
                You&rsquo;re the teacher. Five AI students have read Kate
                Chopin&rsquo;s <em>&ldquo;The Story of an Hour&rdquo;</em> — and they must
                reach three realizations <strong>on their own</strong>. Your only
                tools: open questions, redirects, and silence.
              </p>
              <ul>
                <li>🎙 When a board appears, it&rsquo;s your move — type it (or say it) in your own words.</li>
                <li>🤫 When the room goes quiet, hold the silence. Don&rsquo;t rescue them.</li>
                <li>📝 Turn all three sticky notes green — without lecturing.</li>
              </ul>
              <label className="game-voices-toggle">
                <input type="checkbox" checked={voicesOn}
                  onChange={(e) => setVoicesOn(e.target.checked)} />
                🔊 Student voices — the class speaks its lines aloud (uncheck to read silently)
              </label>
              <button className="game-start" onClick={start}>Take your seat</button>
              <p className="game-title-fine">≈ 3 minutes · a free taste of the Vision&nbsp;Pro simulator</p>
            </div>
          </div>
        )}
      </div>

      {/* The console: where the teacher sits */}
      <div className="game-console">
        {tutorLine && (
          <div className="game-tutor">
            <span className="game-tutor-tag">TUTOR</span>
            <p>{tutorLine}</p>
          </div>
        )}

        {tension !== null && (
          <div className="game-silence">
            <div className="game-silence-cap">The room is silent. Hold it…</div>
            <div className="game-tension"><div style={{ width: `${tension * 100}%` }} /></div>
            <button className="game-break"
              onClick={() => { silenceBroken.current = true; }}>
              Break the silence
            </button>
          </div>
        )}

        {gate && (
          <div key={gateShake} className={`game-gate ${gateShake ? "shake" : ""}`}>
            <div className="game-gate-head">🎙 YOUR MOVE — SAY IT TO THE CLASS</div>
            <div className="game-gate-title">{gate.title}</div>
            <div className="game-gate-chips">
              {gate.suggestions.map((s) => (
                <button key={s} type="button" onClick={() => setInput(s)}>{s}</button>
              ))}
            </div>
            <form className="game-gate-form" onSubmit={onSubmit}>
              <input
                value={input}
                onChange={(e) => setInput(e.target.value)}
                placeholder="…or your own version — the class waits for you"
                autoFocus
                aria-label="Your line to the class"
              />
              {micSupported && (
                <button type="button" className={`game-mic ${listening ? "live" : ""}`}
                  onClick={listen} title="Say it out loud instead">🎤</button>
              )}
              <button type="submit" className="game-say">Say it</button>
            </form>
            {gateHint && <div className="game-gate-hint">Tutor: {gateHint}</div>}
          </div>
        )}

        {why && !gate && tension === null && (
          <div className="game-why">✓ {why}</div>
        )}
      </div>
    </div>
  );
}

// ================= Debrief =================

function Debrief({ score, events, talkRatio, onReplay }: {
  score: number; events: GameEvent[]; talkRatio: number; onReplay: () => void;
}) {
  const moves = [
    { name: "The catalyst", gate: launchGate },
    { name: "The textual tether", gate: windowGate },
    { name: "The redirect", gate: deflectGate },
    { name: "The precise question", gate: bodyGate },
    { name: "The structure question", gate: plantGate },
  ];
  return (
    <div className="game game-debrief">
      <div className="game-debrief-card">
        <h1>Class dismissed.</h1>
        <div className="game-debrief-score">
          ★ {score} <span>/ 400 perfect</span>
        </div>
        <p className="game-debrief-verdict">
          {score >= 400 ? "A flawless Harkness class — every realization came out of a student's mouth."
            : score >= 300 ? "A strong class. Every realization landed — tighten the moves and 400 is yours."
            : "The class got there — but the room learned to lean on you. Play it again and do less."}
        </p>

        <div className="game-debrief-cols">
          <div>
            <h2>The ledger</h2>
            <ul className="game-ledger">
              {events.map((e, i) => (
                <li key={i}>
                  <span>{e.label}</span>
                  <span className={e.pts > 0 ? "good" : e.pts < 0 ? "bad" : ""}>
                    {e.pts > 0 ? `+${e.pts}` : e.pts === 0 ? "—" : e.pts}
                  </span>
                </li>
              ))}
            </ul>
            <p className="game-ledger-talk">
              Your talk share: <strong>{Math.round(talkRatio * 100)}%</strong> of the
              words — masters of the method stay under 10–15%.
            </p>
          </div>
          <div>
            <h2>The five moves you practiced</h2>
            <ul className="game-moves">
              {moves.map((m) => (
                <li key={m.name}>
                  <strong>{m.name}.</strong> {m.gate.whyItWorks}
                </li>
              ))}
            </ul>
          </div>
        </div>

        <p className="game-debrief-fine">
          In the full simulator on Apple&nbsp;Vision&nbsp;Pro, the class isn&rsquo;t
          scripted: eight AI students improvise around <em>your</em> reading and
          <em> your</em> realization nodes, your real voice and gaze are the controls,
          and the debrief scores every intervention.
        </p>
        <div className="game-debrief-ctas">
          <button className="game-start" onClick={onReplay}>Play again</button>
          <Link href="/harkness" className="game-cta-secondary">HarknessAI on Vision Pro →</Link>
        </div>
      </div>
    </div>
  );
}
