"use client";

import { useEffect, useRef } from "react";
import { specFor } from "@/lib/characters";
import { TranscriptEntry } from "@/lib/types";

interface Props {
  entries: TranscriptEntry[];
}

export default function TranscriptLog({ entries }: Props) {
  const logRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    // Scroll the log's own scrollport, never the page (scrollIntoView can
    // drag the whole window when ancestors are scrollable).
    const log = logRef.current;
    if (log) {
      log.scrollTo({ top: log.scrollHeight, behavior: "smooth" });
    }
  }, [entries.length]);

  return (
    <div className="transcript-log" ref={logRef}>
      {entries.length === 0 && (
        <div className="transcript-empty">
          The table is quiet. Start the discussion to hear the cast weigh in.
        </div>
      )}
      {entries.map((entry, i) => {
        if (entry.kind === "note") {
          return (
            <div key={i} className="transcript-note">
              {entry.text}
            </div>
          );
        }
        if (entry.kind === "user") {
          return (
            <div key={i} className="transcript-line user-line">
              <span className="transcript-speaker" style={{ color: "#e6c87a" }}>
                You
              </span>
              <span className="transcript-text">{entry.text}</span>
            </div>
          );
        }
        const tint = specFor(entry.id)?.tint ?? "#d9c9a8";
        return (
          <div key={i} className="transcript-line">
            <span className="transcript-speaker" style={{ color: tint }}>
              {entry.name}
            </span>
            <span className="transcript-text">
              {entry.text}
              {entry.interrupted && <em className="interrupted"> —</em>}
            </span>
          </div>
        );
      })}
    </div>
  );
}
