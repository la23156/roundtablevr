// Shared tarot-card presentation for a character. PRESENTATION-ONLY —
// no drag logic here; a later workstream wraps this for drag-and-drop.
// Styles live in globals.css under "Character cards (workstream A)".

import type { CSSProperties, ReactNode } from "react";
import type { CharacterDef } from "@/lib/characterTypes";

export interface CharacterCardProps {
  def: CharacterDef;
  /** Card width in px (height follows the 5:8 tarot ratio). Default 220. */
  size?: number;
  /** Gallery mode: hover flips the card to the ornate back face. */
  flippable?: boolean;
  /** Optional overlay content (e.g. a delete button) rendered on the front. */
  children?: ReactNode;
}

export default function CharacterCard({
  def,
  size = 220,
  flippable = false,
  children,
}: CharacterCardProps) {
  const style = {
    "--ccard-w": `${size}px`,
    "--ccard-tint": def.tintHex,
  } as CSSProperties;

  return (
    <div
      className={`ccard${flippable ? " ccard-flippable" : ""}`}
      style={style}
    >
      <div className="ccard-inner">
        <div className="ccard-face ccard-front">
          <div
            className="ccard-portrait"
            style={{ backgroundImage: `url(${JSON.stringify(def.portraitURL)})` }}
            role="img"
            aria-label={`Portrait of ${def.name}`}
          />
          {def.isModerator && <div className="ccard-ribbon">Moderator</div>}
          <div className="ccard-plate">
            <div className="ccard-name">{def.name}</div>
            <div className="ccard-archetype">{def.archetype}</div>
          </div>
          {children}
        </div>
        <div className="ccard-face ccard-back" aria-hidden="true" />
      </div>
    </div>
  );
}
