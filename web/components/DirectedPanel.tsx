"use client";

// Directed mode (workstream C): setup editor + live objectives checklist.
// The user defines a goal and 3-7 ordered key points; the moderator teaches
// through them and checks the user's understanding along the way.

import { useEffect, useState } from "react";
import { Direction } from "@/lib/types";

export const MIN_POINTS = 3;
export const MAX_POINTS = 7;

export function isDirectionValid(d: Direction): boolean {
  return (
    d.goal.trim().length > 0 &&
    d.keyPoints.length >= MIN_POINTS &&
    d.keyPoints.length <= MAX_POINTS &&
    d.keyPoints.every((p) => p.trim().length > 0)
  );
}

export const EMPTY_DIRECTION: Direction = {
  goal: "",
  keyPoints: [],
  strictness: "gentle",
  checkInStyle: "perPoint",
};

const PRESETS_KEY = "roundtable.directed.presets";

interface Preset {
  name: string;
  direction: Direction;
}

function loadPresets(): Preset[] {
  try {
    const raw = localStorage.getItem(PRESETS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as Preset[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function storePresets(presets: Preset[]) {
  try {
    localStorage.setItem(PRESETS_KEY, JSON.stringify(presets));
  } catch {
    // storage unavailable — presets are a convenience, never a blocker
  }
}

export interface DirectedPanelProps {
  enabled: boolean;
  onEnabledChange(enabled: boolean): void;
  direction: Direction;
  onDirectionChange(direction: Direction): void;
  covered: number[]; // covered key-point indexes, live from the engine
  running: boolean;
  sessionStarted: boolean; // a directed session has produced transcript turns
}

export default function DirectedPanel({
  enabled,
  onEnabledChange,
  direction,
  onDirectionChange,
  covered,
  running,
  sessionStarted,
}: DirectedPanelProps) {
  const [newPoint, setNewPoint] = useState("");
  const [presets, setPresets] = useState<Preset[]>([]);
  const [presetName, setPresetName] = useState("");
  const [selectedPreset, setSelectedPreset] = useState("");

  useEffect(() => {
    setPresets(loadPresets());
  }, []);

  const set = (patch: Partial<Direction>) =>
    onDirectionChange({ ...direction, ...patch });

  const addPoint = () => {
    const text = newPoint.trim();
    if (!text || direction.keyPoints.length >= MAX_POINTS) return;
    set({ keyPoints: [...direction.keyPoints, text] });
    setNewPoint("");
  };

  const removePoint = (i: number) =>
    set({ keyPoints: direction.keyPoints.filter((_, j) => j !== i) });

  const movePoint = (i: number, delta: -1 | 1) => {
    const j = i + delta;
    if (j < 0 || j >= direction.keyPoints.length) return;
    const pts = [...direction.keyPoints];
    [pts[i], pts[j]] = [pts[j], pts[i]];
    set({ keyPoints: pts });
  };

  const savePreset = () => {
    const name = presetName.trim();
    if (!name || !isDirectionValid(direction)) return;
    const next = [
      ...presets.filter((p) => p.name !== name),
      { name, direction },
    ];
    setPresets(next);
    storePresets(next);
    setSelectedPreset(name);
    setPresetName("");
  };

  const loadPreset = (name: string) => {
    setSelectedPreset(name);
    const preset = presets.find((p) => p.name === name);
    if (preset) onDirectionChange(preset.direction);
  };

  const deletePreset = () => {
    if (!selectedPreset) return;
    const next = presets.filter((p) => p.name !== selectedPreset);
    setPresets(next);
    storePresets(next);
    setSelectedPreset("");
  };

  const valid = isDirectionValid(direction);
  const coveredCount = covered.length;
  const total = direction.keyPoints.length;
  const uncovered = direction.keyPoints
    .map((p, i) => ({ p, i }))
    .filter(({ i }) => !covered.includes(i));

  return (
    <div className="directed-panel">
      <label className="directed-toggle">
        <input
          type="checkbox"
          checked={enabled}
          onChange={(e) => onEnabledChange(e.target.checked)}
          disabled={running}
        />
        <span>Directed session</span>
        <span className="directed-toggle-sub">
          the moderator teaches toward your goal
        </span>
      </label>

      {enabled && !running && (
        <div className="directed-editor">
          <div className="directed-presets">
            <select
              value={selectedPreset}
              onChange={(e) => loadPreset(e.target.value)}
              aria-label="Load a saved preset"
            >
              <option value="">Load preset…</option>
              {presets.map((p) => (
                <option key={p.name} value={p.name}>
                  {p.name}
                </option>
              ))}
            </select>
            {selectedPreset && (
              <button className="dp-mini" onClick={deletePreset} title="Delete preset">
                ✕
              </button>
            )}
            <input
              type="text"
              placeholder="Preset name"
              value={presetName}
              onChange={(e) => setPresetName(e.target.value)}
            />
            <button
              className="dp-mini"
              onClick={savePreset}
              disabled={!presetName.trim() || !valid}
              title="Save current setup as a preset"
            >
              Save
            </button>
          </div>

          <input
            className="directed-goal"
            type="text"
            placeholder="Goal — e.g. Decide whether this deck deserves a second meeting"
            value={direction.goal}
            onChange={(e) => set({ goal: e.target.value })}
          />

          <div className="directed-points">
            {direction.keyPoints.map((point, i) => (
              <div key={i} className="dp-point">
                <span className="dp-point-num">{i + 1}.</span>
                <span className="dp-point-text">{point}</span>
                <button
                  className="dp-mini"
                  onClick={() => movePoint(i, -1)}
                  disabled={i === 0}
                  title="Move up"
                >
                  ▲
                </button>
                <button
                  className="dp-mini"
                  onClick={() => movePoint(i, 1)}
                  disabled={i === direction.keyPoints.length - 1}
                  title="Move down"
                >
                  ▼
                </button>
                <button
                  className="dp-mini"
                  onClick={() => removePoint(i)}
                  title="Remove"
                >
                  ✕
                </button>
              </div>
            ))}
            <div className="dp-add">
              <input
                type="text"
                placeholder={`Add key point (${MIN_POINTS}–${MAX_POINTS}, in teaching order)`}
                value={newPoint}
                onChange={(e) => setNewPoint(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && addPoint()}
                disabled={direction.keyPoints.length >= MAX_POINTS}
              />
              <button
                className="dp-mini"
                onClick={addPoint}
                disabled={
                  !newPoint.trim() || direction.keyPoints.length >= MAX_POINTS
                }
              >
                Add
              </button>
            </div>
          </div>

          <div className="dp-radio-row">
            <span className="dp-radio-label">Steering</span>
            <label>
              <input
                type="radio"
                name="dp-strictness"
                checked={direction.strictness === "gentle"}
                onChange={() => set({ strictness: "gentle" })}
              />
              Gentle
            </label>
            <label>
              <input
                type="radio"
                name="dp-strictness"
                checked={direction.strictness === "firm"}
                onChange={() => set({ strictness: "firm" })}
              />
              Firm
            </label>
          </div>
          <div className="dp-radio-row">
            <span className="dp-radio-label">Check-ins</span>
            <label>
              <input
                type="radio"
                name="dp-checkin"
                checked={direction.checkInStyle === "perPoint"}
                onChange={() => set({ checkInStyle: "perPoint" })}
              />
              After every point
            </label>
            <label>
              <input
                type="radio"
                name="dp-checkin"
                checked={direction.checkInStyle === "periodic"}
                onChange={() => set({ checkInStyle: "periodic" })}
              />
              Periodically
            </label>
          </div>

          {!valid && (
            <div className="dp-validation">
              Set a goal and {MIN_POINTS}–{MAX_POINTS} key points to start a
              directed session.
            </div>
          )}
        </div>
      )}

      {enabled && sessionStarted && total > 0 && (
        <div className="directed-objectives">
          <div className="dp-obj-heading">Objectives</div>
          {direction.keyPoints.map((point, i) => {
            const done = covered.includes(i);
            return (
              <div key={i} className={`dp-obj${done ? " covered" : ""}`}>
                <span className="dp-obj-check">{done ? "✓" : ""}</span>
                <span className="dp-obj-text">{point}</span>
              </div>
            );
          })}
          {!running && (
            <div className="dp-summary">
              {coveredCount} of {total} key points covered
              {uncovered.length > 0 && (
                <span className="dp-summary-missing">
                  {" "}
                  — still open: {uncovered.map(({ p }) => p).join("; ")}
                </span>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
