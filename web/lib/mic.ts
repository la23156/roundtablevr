// Always-listening microphone with local voice-activity detection.
//
// Ideal path (Deepgram Flux streaming with a short-lived browser token) is
// unavailable: the account key can't mint temp tokens and Vercel functions
// can't proxy WebSockets. Instead: an analyser node watches RMS energy; a
// MediaRecorder runs continuously and is finalized at each speech→silence
// boundary, and the complete utterance goes to /api/stt (nova-3). The Web
// Speech API, where present, supplies a live interim transcript for display.

export interface MicCallbacks {
  onLevel(level: number): void; // 0..1 smoothed input level
  onInterim(text: string | null): void;
  onFinal(text: string): void;
  onState(state: "idle" | "listening" | "speech" | "processing"): void;
}

const SPEECH_THRESHOLD = 0.028; // RMS gate — above this counts as voice
const SPEECH_MIN_MS = 200; // sustained voice needed to open an utterance
const SILENCE_END_MS = 750; // silence needed to close an utterance
const MAX_IDLE_RECORD_MS = 15000; // recycle recorder during long silence

type SpeechRecognitionLike = {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  start(): void;
  stop(): void;
  onresult: ((event: unknown) => void) | null;
  onend: (() => void) | null;
  onerror: (() => void) | null;
};

export class MicController {
  private stream: MediaStream | null = null;
  private ctx: AudioContext | null = null;
  private analyser: AnalyserNode | null = null;
  private recorder: MediaRecorder | null = null;
  private recorderStartedAt = 0;
  private timer: number | null = null;
  private recognition: SpeechRecognitionLike | null = null;

  private speechActive = false;
  private voiceSince = 0;
  private lastVoiceAt = 0;
  private active = false;

  constructor(private cb: MicCallbacks) {}

  get isActive() {
    return this.active;
  }

  async start(): Promise<void> {
    if (this.active) return;
    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
    });
    this.active = true;
    this.ctx = new AudioContext();
    const source = this.ctx.createMediaStreamSource(this.stream);
    this.analyser = this.ctx.createAnalyser();
    this.analyser.fftSize = 1024;
    source.connect(this.analyser);

    this.startRecorder();
    this.startInterimRecognition();
    this.cb.onState("listening");

    const buf = new Float32Array(this.analyser.fftSize);
    let smoothed = 0;
    this.timer = window.setInterval(() => {
      if (!this.analyser || !this.active) return;
      this.analyser.getFloatTimeDomainData(buf);
      let sum = 0;
      for (let i = 0; i < buf.length; i++) sum += buf[i] * buf[i];
      const rms = Math.sqrt(sum / buf.length);
      smoothed = smoothed * 0.7 + rms * 0.3;
      this.cb.onLevel(Math.min(1, smoothed * 12));

      const now = performance.now();
      if (smoothed > SPEECH_THRESHOLD) {
        if (this.voiceSince === 0) this.voiceSince = now;
        this.lastVoiceAt = now;
        if (!this.speechActive && now - this.voiceSince > SPEECH_MIN_MS) {
          this.speechActive = true;
          this.cb.onState("speech");
        }
      } else {
        this.voiceSince = 0;
        if (this.speechActive && now - this.lastVoiceAt > SILENCE_END_MS) {
          this.speechActive = false;
          this.finalizeUtterance();
        } else if (
          !this.speechActive &&
          now - this.recorderStartedAt > MAX_IDLE_RECORD_MS
        ) {
          // Long silence: recycle the recorder so utterance blobs stay small.
          this.restartRecorder(false);
        }
      }
    }, 50);
  }

  stop(): void {
    this.active = false;
    if (this.timer !== null) window.clearInterval(this.timer);
    this.timer = null;
    try {
      this.recognition?.stop();
    } catch {
      // recognition may already be stopped
    }
    this.recognition = null;
    if (this.recorder && this.recorder.state !== "inactive") {
      this.recorder.onstop = null;
      this.recorder.stop();
    }
    this.recorder = null;
    this.stream?.getTracks().forEach((t) => t.stop());
    this.stream = null;
    void this.ctx?.close();
    this.ctx = null;
    this.speechActive = false;
    this.cb.onLevel(0);
    this.cb.onInterim(null);
    this.cb.onState("idle");
  }

  // MARK: - Recorder lifecycle

  private preferredMime(): string | undefined {
    const options = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4"];
    return options.find((m) => MediaRecorder.isTypeSupported(m));
  }

  private startRecorder() {
    if (!this.stream) return;
    const mime = this.preferredMime();
    this.recorder = new MediaRecorder(
      this.stream,
      mime ? { mimeType: mime } : undefined
    );
    const parts: Blob[] = [];
    this.recorder.ondataavailable = (e) => {
      if (e.data.size > 0) parts.push(e.data);
    };
    this.recorder.onstop = () => {
      const shouldSend = (this.recorder as unknown as { _send?: boolean })?._send;
      const blob = new Blob(parts, { type: mime ?? "audio/webm" });
      if (shouldSend && blob.size > 1000) void this.transcribe(blob);
      if (this.active) this.startRecorder();
    };
    this.recorder.start(250);
    this.recorderStartedAt = performance.now();
  }

  private restartRecorder(send: boolean) {
    if (!this.recorder || this.recorder.state === "inactive") return;
    (this.recorder as unknown as { _send?: boolean })._send = send;
    this.recorder.stop(); // onstop restarts a fresh recorder
  }

  private finalizeUtterance() {
    this.cb.onState("processing");
    this.restartRecorder(true);
  }

  private async transcribe(blob: Blob) {
    try {
      const res = await fetch("/api/stt", {
        method: "POST",
        headers: { "Content-Type": blob.type || "audio/webm" },
        body: blob,
      });
      const data = (await res.json()) as { transcript?: string };
      const text = (data.transcript ?? "").trim();
      this.cb.onInterim(null);
      if (this.active) this.cb.onState("listening");
      if (text) this.cb.onFinal(text);
    } catch {
      if (this.active) this.cb.onState("listening");
    }
  }

  // MARK: - Live interim display (Web Speech API, best-effort)

  private startInterimRecognition() {
    const w = window as unknown as {
      SpeechRecognition?: new () => SpeechRecognitionLike;
      webkitSpeechRecognition?: new () => SpeechRecognitionLike;
    };
    const Ctor = w.SpeechRecognition ?? w.webkitSpeechRecognition;
    if (!Ctor) return;
    try {
      const rec = new Ctor();
      rec.continuous = true;
      rec.interimResults = true;
      rec.lang = "en-US";
      rec.onresult = (event) => {
        const e = event as {
          resultIndex: number;
          results: ArrayLike<{ 0: { transcript: string }; isFinal: boolean }>;
        };
        let interim = "";
        for (let i = e.resultIndex; i < e.results.length; i++) {
          if (!e.results[i].isFinal) interim += e.results[i][0].transcript;
        }
        if (interim.trim()) this.cb.onInterim(interim.trim());
      };
      rec.onend = () => {
        if (this.active && this.recognition === rec) {
          try {
            rec.start(); // keep it always-on
          } catch {
            // ignored — recognition restart can race its own teardown
          }
        }
      };
      rec.onerror = () => {
        // non-fatal; onend handles restart
      };
      rec.start();
      this.recognition = rec;
    } catch {
      this.recognition = null;
    }
  }
}
