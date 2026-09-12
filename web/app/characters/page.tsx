"use client";

// /characters — character creator + gallery (workstream A).
// Personality first: worldview + speech style get the big textareas.

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import CharacterCard from "@/components/CharacterCard";
import {
  BASE_BODIES,
  CURATED_VOICES,
  TINT_PRESETS,
  type BaseBody,
  type CharacterDef,
} from "@/lib/characterTypes";

const AUDITION_LINE =
  "Every table needs a voice like mine. Pull up a chair, and let us see where the argument leads.";

const WORLDVIEW_PLACEHOLDER =
  "What do they believe about how the world works? e.g. “Incentives explain most things people attribute to ideals. Suspicious of grand narratives; delighted by inconvenient statistics.” — or — “Nothing is unprecedented; everything rhymes. The past is the only laboratory we have for human nature.”";

const SPEECH_PLACEHOLDER =
  "How do they talk? e.g. “Dry, precise, lightly sarcastic. Loves ‘the numbers say otherwise’. Short sentences.” — or — “Warm storyteller, opens with ‘There’s a story about…’, connects the present to concrete historical moments.”";

const APPEARANCE_PLACEHOLDER =
  "Describe their look for the portrait painter, e.g. “a weathered sea captain in her sixties, salt-grey braid, brass-buttoned navy coat, knowing half-smile”";

export default function CharactersPage() {
  // Gallery
  const [characters, setCharacters] = useState<CharacterDef[] | null>(null);
  const [galleryError, setGalleryError] = useState("");

  // Form
  const [name, setName] = useState("");
  const [archetype, setArchetype] = useState("");
  const [bio, setBio] = useState("");
  const [worldview, setWorldview] = useState("");
  const [speechStyle, setSpeechStyle] = useState("");
  const [voiceID, setVoiceID] = useState(CURATED_VOICES[0].id);
  const [tintHex, setTintHex] = useState(TINT_PRESETS[5]);
  const [baseBody, setBaseBody] = useState<BaseBody>("brunette");
  const [appearance, setAppearance] = useState("");

  // Portrait preview
  const [portraitDataURL, setPortraitDataURL] = useState("");
  const [generating, setGenerating] = useState(false);

  // Audition
  const [auditioning, setAuditioning] = useState(""); // voice id being fetched
  const [playing, setPlaying] = useState(""); // voice id currently audible
  const audioRef = useRef<HTMLAudioElement | null>(null);

  // Save
  const [saving, setSaving] = useState(false);
  const [status, setStatus] = useState("");
  const [statusOk, setStatusOk] = useState(false);

  const refresh = useCallback(async () => {
    try {
      const res = await fetch("/api/characters", { cache: "no-store" });
      const data = (await res.json()) as {
        characters?: CharacterDef[];
        error?: string;
      };
      if (!res.ok || !data.characters) {
        throw new Error(data.error ?? `HTTP ${res.status}`);
      }
      setCharacters(data.characters);
      setGalleryError("");
    } catch (err) {
      setGalleryError(
        err instanceof Error ? err.message : "Could not load characters"
      );
    }
  }, []);

  useEffect(() => {
    void refresh();
    return () => {
      audioRef.current?.pause();
    };
  }, [refresh]);

  async function audition(id: string) {
    audioRef.current?.pause();
    setPlaying("");
    setAuditioning(id);
    try {
      const res = await fetch("/api/tts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: AUDITION_LINE, voiceID: id }),
      });
      if (!res.ok) throw new Error(`TTS HTTP ${res.status}`);
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const audio = new Audio(url);
      audioRef.current = audio;
      audio.onended = () => {
        setPlaying("");
        URL.revokeObjectURL(url);
      };
      setPlaying(id);
      await audio.play();
    } catch {
      setPlaying("");
    } finally {
      setAuditioning("");
    }
  }

  async function generate() {
    if (!appearance.trim() || generating) return;
    setGenerating(true);
    setStatus("Painting the portrait…");
    setStatusOk(false);
    try {
      const res = await fetch("/api/portrait", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ appearance: appearance.trim() }),
      });
      const data = (await res.json()) as { dataURL?: string; error?: string };
      if (!res.ok || !data.dataURL) {
        throw new Error(data.error ?? `HTTP ${res.status}`);
      }
      setPortraitDataURL(data.dataURL);
      setStatus("Portrait ready — regenerate or save.");
      setStatusOk(true);
    } catch (err) {
      setStatus(
        `Portrait failed: ${err instanceof Error ? err.message : "unknown error"}`
      );
      setStatusOk(false);
    } finally {
      setGenerating(false);
    }
  }

  async function save() {
    if (saving) return;
    setSaving(true);
    setStatus("Saving…");
    setStatusOk(false);
    try {
      const res = await fetch("/api/characters", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name,
          archetype,
          bio,
          worldview,
          speechStyle,
          voiceID,
          tintHex,
          baseBody,
          portraitDataURL: portraitDataURL || undefined,
          appearance: appearance.trim() || undefined,
        }),
      });
      const data = (await res.json()) as {
        character?: CharacterDef;
        error?: string;
      };
      if (!res.ok || !data.character) {
        throw new Error(data.error ?? `HTTP ${res.status}`);
      }
      setStatus(`${data.character.name} has joined the roster.`);
      setStatusOk(true);
      setName("");
      setArchetype("");
      setBio("");
      setWorldview("");
      setSpeechStyle("");
      setAppearance("");
      setPortraitDataURL("");
      await refresh();
    } catch (err) {
      setStatus(
        `Save failed: ${err instanceof Error ? err.message : "unknown error"}`
      );
      setStatusOk(false);
    } finally {
      setSaving(false);
    }
  }

  async function remove(id: string, charName: string) {
    if (!window.confirm(`Remove ${charName} from the roster?`)) return;
    try {
      const res = await fetch(`/api/characters/${encodeURIComponent(id)}`, {
        method: "DELETE",
      });
      if (!res.ok) {
        const data = (await res.json()) as { error?: string };
        throw new Error(data.error ?? `HTTP ${res.status}`);
      }
      await refresh();
    } catch (err) {
      setGalleryError(
        err instanceof Error ? err.message : "Delete failed"
      );
    }
  }

  const canSave =
    name.trim() !== "" &&
    archetype.trim() !== "" &&
    worldview.trim() !== "" &&
    speechStyle.trim() !== "" &&
    (portraitDataURL !== "" || appearance.trim() !== "") &&
    !saving;

  return (
    <div className="chars-shell">
      <Link href="/table" className="chars-back">
        &larr; back to the table
      </Link>

      <header className="masthead">
        <h1>The Roster</h1>
        <p className="tagline">
          Summon a new mind to the table — personality first, portrait second.
        </p>
      </header>

      <div className="chars-columns">
        {/* ---- Creator ---- */}
        <section className="chars-form-pane" aria-label="Character creator">
          <div className="chars-row2">
            <div className="chars-field">
              <label htmlFor="c-name">Name</label>
              <input
                id="c-name"
                className="chars-input"
                value={name}
                maxLength={80}
                placeholder="e.g. Captain Ines Marlowe"
                onChange={(e) => setName(e.target.value)}
              />
            </div>
            <div className="chars-field">
              <label htmlFor="c-arch">Archetype</label>
              <input
                id="c-arch"
                className="chars-input"
                value={archetype}
                maxLength={60}
                placeholder="e.g. The Navigator"
                onChange={(e) => setArchetype(e.target.value)}
              />
            </div>
          </div>

          <div className="chars-field">
            <label htmlFor="c-bio">Bio</label>
            <input
              id="c-bio"
              className="chars-input"
              value={bio}
              maxLength={300}
              placeholder="One line the table will remember them by."
              onChange={(e) => setBio(e.target.value)}
            />
          </div>

          <div className="chars-field">
            <label htmlFor="c-worldview">Worldview</label>
            <p className="chars-sublabel">
              The heart of the character — how they see the world.
            </p>
            <textarea
              id="c-worldview"
              className="chars-textarea tall"
              value={worldview}
              maxLength={2000}
              placeholder={WORLDVIEW_PLACEHOLDER}
              onChange={(e) => setWorldview(e.target.value)}
            />
          </div>

          <div className="chars-field">
            <label htmlFor="c-speech">Speech style</label>
            <p className="chars-sublabel">
              Cadence, quirks, favorite phrases — what makes them audible.
            </p>
            <textarea
              id="c-speech"
              className="chars-textarea tall"
              value={speechStyle}
              maxLength={2000}
              placeholder={SPEECH_PLACEHOLDER}
              onChange={(e) => setSpeechStyle(e.target.value)}
            />
          </div>

          <div className="chars-field">
            <span className="chars-label">Voice</span>
            <div className="voice-list" role="radiogroup" aria-label="Voice">
              {CURATED_VOICES.map((v) => (
                <div
                  key={v.id}
                  className={`voice-row${voiceID === v.id ? " selected" : ""}`}
                  role="radio"
                  aria-checked={voiceID === v.id}
                  tabIndex={0}
                  onClick={() => setVoiceID(v.id)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") setVoiceID(v.id);
                  }}
                >
                  <span className="voice-name">{v.label}</span>
                  <span className="voice-blurb">{v.blurb}</span>
                  <button
                    type="button"
                    className={`voice-audition${playing === v.id ? " playing" : ""}`}
                    title={`Audition ${v.label}`}
                    aria-label={`Audition ${v.label}`}
                    disabled={auditioning !== ""}
                    onClick={(e) => {
                      e.stopPropagation();
                      void audition(v.id);
                    }}
                  >
                    {auditioning === v.id ? "…" : "▶"}
                  </button>
                </div>
              ))}
            </div>
          </div>

          <div className="chars-field">
            <span className="chars-label">Tint</span>
            <div className="tint-swatches">
              {TINT_PRESETS.map((hex) => (
                <button
                  key={hex}
                  type="button"
                  className={`tint-swatch${tintHex === hex ? " selected" : ""}`}
                  style={{ background: hex, "--tint": hex } as React.CSSProperties}
                  title={hex}
                  aria-label={`Tint ${hex}`}
                  onClick={() => setTintHex(hex)}
                />
              ))}
            </div>
          </div>

          <div className="chars-field">
            <span className="chars-label">Base body</span>
            <p className="chars-sublabel">
              The 3D body used for this character in VR. (Thumbnails are
              stand-ins from the current cast.)
            </p>
            <div className="body-picker">
              {BASE_BODIES.map((b) => (
                <div
                  key={b.id}
                  className={`body-option${baseBody === b.id ? " selected" : ""}`}
                  role="radio"
                  aria-checked={baseBody === b.id}
                  tabIndex={0}
                  onClick={() => setBaseBody(b.id)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") setBaseBody(b.id);
                  }}
                >
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img className="body-thumb" src={b.standIn} alt="" />
                  <div className="body-label">{b.label}</div>
                </div>
              ))}
            </div>
          </div>

          <div className="chars-field">
            <label htmlFor="c-appearance">Appearance</label>
            <textarea
              id="c-appearance"
              className="chars-textarea"
              value={appearance}
              maxLength={600}
              placeholder={APPEARANCE_PLACEHOLDER}
              onChange={(e) => setAppearance(e.target.value)}
            />
          </div>

          <div className="portrait-actions">
            <button
              type="button"
              className="btn"
              disabled={!appearance.trim() || generating}
              onClick={() => void generate()}
            >
              {generating
                ? "Painting…"
                : portraitDataURL
                  ? "Regenerate portrait"
                  : "Generate portrait"}
            </button>
            <button
              type="button"
              className="btn btn-primary"
              disabled={!canSave}
              onClick={() => void save()}
            >
              {saving ? "Saving…" : "Save to roster"}
            </button>
          </div>

          {portraitDataURL && (
            <div className="portrait-preview">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={portraitDataURL} alt="Generated portrait preview" />
            </div>
          )}

          {status && (
            <p className={`chars-status${statusOk ? " ok" : ""}`}>{status}</p>
          )}
        </section>

        {/* ---- Gallery ---- */}
        <section className="chars-gallery-pane" aria-label="Character gallery">
          {galleryError && <p className="error-banner">{galleryError}</p>}
          {characters === null && !galleryError && (
            <p className="chars-status">Fetching the roster&hellip;</p>
          )}
          <div className="chars-gallery-grid">
            {(characters ?? []).map((c) => (
              <div className="chars-gallery-cell" key={c.id}>
                <CharacterCard def={c} size={200} flippable>
                  {!c.builtIn && (
                    <button
                      type="button"
                      className="ccard-delete"
                      title={`Delete ${c.name}`}
                      aria-label={`Delete ${c.name}`}
                      onClick={() => void remove(c.id, c.name)}
                    >
                      &times;
                    </button>
                  )}
                </CharacterCard>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
