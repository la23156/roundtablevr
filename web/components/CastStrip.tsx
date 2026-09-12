"use client";

import { CAST } from "@/lib/characters";

interface Props {
  activeSpeaker: string | null;
}

export default function CastStrip({ activeSpeaker }: Props) {
  return (
    <div className="cast-strip">
      {CAST.map((c) => {
        const active = c.id === activeSpeaker;
        const initials = c.name
          .split(" ")
          .filter((w) => /^[A-Z]/.test(w))
          .slice(-2)
          .map((w) => w[0])
          .join("");
        return (
          <div key={c.id} className={`cast-tile${active ? " active" : ""}`}>
            <div
              className="cast-avatar"
              style={{
                borderColor: c.tint,
                color: c.tint,
                boxShadow: active ? `0 0 18px ${c.tint}55` : undefined,
              }}
            >
              {initials}
              <span className={`speak-dot${active ? " on" : ""}`} />
            </div>
            <div className="cast-name">{c.name.split(" ").slice(-1)[0]}</div>
            <div className="cast-archetype">{c.archetype}</div>
          </div>
        );
      })}
    </div>
  );
}
