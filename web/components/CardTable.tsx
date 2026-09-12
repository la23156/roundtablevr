"use client";

// The card table (workstream B): build the discussion roster by dragging
// character tarot cards onto a 2.5D perspective table. Seat/tray rules live
// in lib/rosterState.ts (pure, unit-testable); this component is the DOM,
// pointer, and animation layer. Cards are workstream A's CharacterCard,
// reused at a compact size. Styles: globals.css under
// "Card roster (workstream B)".

import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type KeyboardEvent as ReactKeyboardEvent,
  type PointerEvent as ReactPointerEvent,
} from "react";
import CharacterCard from "@/components/CharacterCard";
import { BUILT_IN_CHARACTERS, type CharacterDef } from "@/lib/characterTypes";
import {
  MIN_SEATED,
  SEAT_COUNT,
  canStart,
  seat,
  seatedIds,
  toggleSeat,
  trayIds,
  unseat,
  initialSeats,
  type Seats,
} from "@/lib/rosterState";

interface Props {
  /** Cast id of the character currently speaking (green glow on their card). */
  activeSpeaker: string | null;
  /** Fires whenever the seated set (or fetched roster) changes: the seated
   *  CharacterDefs in seat order, plus the full roster for lookups. */
  onCastChange: (seated: CharacterDef[], roster: CharacterDef[]) => void;
}

/** Seat anchor points on the table arc: % offsets within the scene, plus a
 *  depth scale (smaller = further away). Slot 0 = head of the table. */
const SEAT_POS = [
  { x: 50, y: 0, s: 0.84 }, // 0 — moderator's chair, back center
  { x: 26, y: 13, s: 0.92 },
  { x: 74, y: 13, s: 0.92 },
  { x: 9, y: 31, s: 1 },
  { x: 91, y: 31, s: 1 },
];

const DRAG_THRESHOLD = 6; // px of pointer travel before a press becomes a drag

interface DragState {
  id: string;
  fromSeat: number; // -1 = came from the tray
  w: number;
  h: number;
  x: number; // pointer position (client coords)
  y: number;
  dx: number; // pointer offset within the card
  dy: number;
}

interface FlyState {
  id: string;
  fx: number; // from (fixed coords)
  fy: number;
  w: number;
  phase: "measure" | "go";
  tx?: number;
  ty?: number;
  tw?: number;
}

const LockBadge = () => (
  <div className="rcard-lock" title="The moderator anchors the table">
    <svg viewBox="0 0 24 24" width="12" height="12" aria-hidden="true">
      <path
        fill="currentColor"
        d="M12 2a5 5 0 0 0-5 5v3H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8a2 2 0 0 0-2-2h-1V7a5 5 0 0 0-5-5Zm-3 8V7a3 3 0 1 1 6 0v3H9Z"
      />
    </svg>
    <span>Seated</span>
  </div>
);

export default function CardTable({ activeSpeaker, onCastChange }: Props) {
  const [roster, setRoster] = useState<CharacterDef[]>(BUILT_IN_CHARACTERS);
  const [seats, setSeats] = useState<Seats>(() => initialSeats());
  const [drag, setDrag] = useState<DragState | null>(null);
  const [hoverSeat, setHoverSeat] = useState<number | null>(null);
  const [fly, setFly] = useState<FlyState | null>(null);
  const [settleId, setSettleId] = useState<string | null>(null);
  const [cardW, setCardW] = useState(88);
  const [rootW, setRootW] = useState(440);

  const rootRef = useRef<HTMLDivElement>(null);
  const seatEls = useRef<(HTMLDivElement | null)[]>([]);
  const cardEls = useRef(new Map<string, HTMLDivElement>());
  const pressRef = useRef<{
    id: string;
    fromSeat: number;
    x0: number;
    y0: number;
    rect: DOMRect;
    pointerId: number;
  } | null>(null);
  const seatsRef = useRef(seats);
  seatsRef.current = seats;
  const dragRef = useRef(drag);
  dragRef.current = drag;
  const hoverRef = useRef(hoverSeat);
  hoverRef.current = hoverSeat;
  const flyRef = useRef(fly);
  flyRef.current = fly;
  const settleTimer = useRef<number | null>(null);

  const defById = useMemo(() => {
    const m = new Map<string, CharacterDef>();
    for (const c of roster) m.set(c.id, c);
    return m;
  }, [roster]);

  // Fetch the full roster (built-ins + web-created customs) on mount.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch("/api/characters", { cache: "no-store" });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = (await res.json()) as { characters?: CharacterDef[] };
        if (!cancelled && Array.isArray(data.characters) && data.characters.length > 0) {
          setRoster(data.characters);
        }
      } catch {
        // Offline / store hiccup: the built-in five remain available.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Responsive card size: ~1/5 of the pane width, clamped.
  useEffect(() => {
    const el = rootRef.current;
    if (!el || typeof ResizeObserver === "undefined") return;
    const ro = new ResizeObserver(() => {
      const w = el.clientWidth;
      if (w > 0) {
        setRootW(w);
        setCardW(Math.max(66, Math.min(100, Math.round(w * 0.195))));
      }
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // Report the seated cast upward (page.tsx feeds it to the engine).
  useEffect(() => {
    const seated = seatedIds(seats)
      .map((id) => defById.get(id))
      .filter((c): c is CharacterDef => c !== undefined);
    onCastChange(seated, roster);
  }, [seats, roster, defById, onCastChange]);

  useEffect(() => {
    return () => {
      if (settleTimer.current !== null) window.clearTimeout(settleTimer.current);
    };
  }, []);

  const pop = useCallback((id: string) => {
    if (settleTimer.current !== null) window.clearTimeout(settleTimer.current);
    setSettleId(id);
    settleTimer.current = window.setTimeout(() => setSettleId(null), 480);
  }, []);

  /** Nearest droppable seat within reach of the pointer, or null. */
  const findHoverSeat = useCallback((x: number, y: number, d: DragState) => {
    const radius = Math.max(80, d.w * 0.95);
    let best: number | null = null;
    let bestDist = Infinity;
    for (let i = 0; i < SEAT_COUNT; i++) {
      const occupant = seatsRef.current[i];
      if (occupant !== null && occupant !== d.id) continue; // taken
      const el = seatEls.current[i];
      if (!el) continue;
      const r = el.getBoundingClientRect();
      const cx = r.left + r.width / 2;
      const cy = r.top + r.height / 2;
      const dist = Math.hypot(x - cx, y - cy);
      if (dist < radius && dist < bestDist) {
        best = i;
        bestDist = dist;
      }
    }
    return best;
  }, []);

  const beginPress = useCallback(
    (e: ReactPointerEvent<HTMLDivElement>, id: string, fromSeat: number) => {
      if (flyRef.current || pressRef.current) return;
      if (e.button !== 0 && e.pointerType === "mouse") return;
      const el = e.currentTarget;
      try {
        el.setPointerCapture(e.pointerId);
      } catch {
        // capture is best-effort
      }
      pressRef.current = {
        id,
        fromSeat,
        x0: e.clientX,
        y0: e.clientY,
        rect: el.getBoundingClientRect(),
        pointerId: e.pointerId,
      };
    },
    []
  );

  const movePress = useCallback(
    (e: ReactPointerEvent<HTMLDivElement>) => {
      const p = pressRef.current;
      if (!p || p.pointerId !== e.pointerId) return;
      const d = dragRef.current;
      if (!d) {
        if (
          Math.hypot(e.clientX - p.x0, e.clientY - p.y0) >= DRAG_THRESHOLD
        ) {
          const next: DragState = {
            id: p.id,
            fromSeat: p.fromSeat,
            w: p.rect.width,
            h: p.rect.height,
            x: e.clientX,
            y: e.clientY,
            dx: p.x0 - p.rect.left,
            dy: p.y0 - p.rect.top,
          };
          setDrag(next);
          setHoverSeat(findHoverSeat(e.clientX, e.clientY, next));
        }
        return;
      }
      setDrag({ ...d, x: e.clientX, y: e.clientY });
      setHoverSeat(findHoverSeat(e.clientX, e.clientY, d));
    },
    [findHoverSeat]
  );

  /** Send the floating card gliding to wherever `id` now lives. */
  const startFly = useCallback((d: DragState) => {
    setFly({
      id: d.id,
      fx: d.x - d.dx,
      fy: d.y - d.dy,
      w: d.w,
      phase: "measure",
    });
  }, []);

  const endPress = useCallback(
    (e: ReactPointerEvent<HTMLDivElement>, cancelled = false) => {
      const p = pressRef.current;
      if (!p || p.pointerId !== e.pointerId) return;
      pressRef.current = null;
      const d = dragRef.current;

      if (!d || d.id !== p.id) {
        // A plain click/tap: toggle between tray and first free seat.
        if (!cancelled) {
          const next = toggleSeat(seatsRef.current, p.id);
          if (next !== seatsRef.current) {
            setSeats(next);
            pop(p.id);
          }
        }
        return;
      }

      // A drag ends: seat it, remove it, or send it home.
      if (!cancelled) {
        const hs = hoverRef.current;
        let next = seatsRef.current;
        if (hs !== null) {
          next = seat(next, d.id, hs);
        } else if (d.fromSeat >= 0) {
          next = unseat(next, d.id); // dragged off the table → back to tray
        }
        if (next !== seatsRef.current) setSeats(next);
      }
      setDrag(null);
      setHoverSeat(null);
      startFly(d);
    },
    [pop, startFly]
  );

  // Fly-back/snap animation: measure the card's resting spot after the
  // seats update renders, then glide the floating card onto it.
  useLayoutEffect(() => {
    if (fly?.phase !== "measure") return;
    const el = cardEls.current.get(fly.id);
    if (!el) {
      setFly(null);
      return;
    }
    const r = el.getBoundingClientRect();
    if (Math.abs(r.left - fly.fx) < 2 && Math.abs(r.top - fly.fy) < 2) {
      setFly(null); // already home — nothing to animate
      return;
    }
    const raf = requestAnimationFrame(() => {
      setFly((f) =>
        f && f.phase === "measure"
          ? { ...f, phase: "go", tx: r.left, ty: r.top, tw: r.width }
          : f
      );
    });
    return () => cancelAnimationFrame(raf);
  }, [fly]);

  // Safety net: never let a missed transitionend strand the floating card.
  useEffect(() => {
    if (fly?.phase !== "go") return;
    const t = window.setTimeout(() => {
      setFly((f) => (f && f.phase === "go" ? null : f));
    }, 600);
    return () => window.clearTimeout(t);
  }, [fly?.phase]);

  const finishFly = useCallback(() => {
    const f = flyRef.current;
    if (!f) return;
    setFly(null);
    pop(f.id);
  }, [pop]);

  const seated = seatedIds(seats);
  const tray = trayIds(
    roster.map((c) => c.id),
    seats
  );
  const ready = canStart(seats);
  const fanMid = (tray.length - 1) / 2;
  // Fan overlap: cards overlap just enough that the whole tray always fits
  // the pane width, no matter how many custom characters exist.
  const trayCardW = Math.round(cardW * 0.94);
  const trayStep =
    tray.length > 1
      ? Math.min(
          trayCardW - 14,
          Math.max(trayCardW * 0.34, (rootW - 16 - trayCardW) / (tray.length - 1))
        )
      : trayCardW;
  const trayMargin = Math.min(0, (trayStep - trayCardW) / 2);

  const registerCard = (id: string) => (el: HTMLDivElement | null) => {
    if (el) cardEls.current.set(id, el);
    else cardEls.current.delete(id);
  };

  const cardKeyToggle = (id: string) => (e: ReactKeyboardEvent) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      const next = toggleSeat(seatsRef.current, id);
      if (next !== seatsRef.current) {
        setSeats(next);
        pop(id);
      }
    }
  };

  return (
    <div
      className={`card-table${drag ? " dragging" : ""}`}
      ref={rootRef}
      style={{ "--rcard-w": `${cardW}px` } as CSSProperties}
    >
      <div
        className="rtable-scene"
        style={{ height: `${Math.round(cardW * 1.6 + cardW * 1.6 * 0.31 + 14)}px` }}
      >
        <div className="rtable-surface" aria-hidden="true">
          <div className="rtable-felt" />
        </div>

        {SEAT_POS.map((pos, i) => {
          const occupantId = seats[i];
          const def = occupantId ? defById.get(occupantId) : undefined;
          const w = Math.round(cardW * pos.s);
          const isModeratorSeat = i === 0 && def?.isModerator;
          const beingDragged = drag?.id === occupantId;
          const hidden =
            occupantId !== null &&
            (beingDragged || fly?.id === occupantId);
          const speaking =
            occupantId !== null && occupantId === activeSpeaker;
          return (
            <div
              key={i}
              className={`rtable-seat${hoverSeat === i ? " hot" : ""}${occupantId ? " occupied" : ""}`}
              style={{
                left: `${pos.x}%`,
                top: `${pos.y}%`,
                width: `${w}px`,
                height: `${Math.round(w * 1.6)}px`,
                zIndex: 2 + i,
              }}
              ref={(el) => {
                seatEls.current[i] = el;
              }}
            >
              <div className="seat-ring" aria-hidden="true" />
              {def && (
                <div
                  className={`rcard-holder seated-card${speaking ? " speaking" : ""}${settleId === def.id ? " settle" : ""}${hidden ? " ghost-hidden" : ""}${isModeratorSeat ? " locked" : ""}`}
                  ref={registerCard(def.id)}
                  role="button"
                  tabIndex={isModeratorSeat ? -1 : 0}
                  aria-label={
                    isModeratorSeat
                      ? `${def.name}, moderator, seated (locked)`
                      : `${def.name}, seated — activate to return to the tray`
                  }
                  onPointerDown={
                    isModeratorSeat ? undefined : (e) => beginPress(e, def.id, i)
                  }
                  onPointerMove={isModeratorSeat ? undefined : movePress}
                  onPointerUp={isModeratorSeat ? undefined : (e) => endPress(e)}
                  onPointerCancel={
                    isModeratorSeat ? undefined : (e) => endPress(e, true)
                  }
                  onKeyDown={isModeratorSeat ? undefined : cardKeyToggle(def.id)}
                >
                  <CharacterCard def={def} size={w}>
                    {isModeratorSeat && <LockBadge />}
                  </CharacterCard>
                  <span className={`speak-orb${speaking ? " on" : ""}`} />
                </div>
              )}
            </div>
          );
        })}
      </div>

      <div className="rtable-status">
        {ready ? (
          <>Table of {seated.length} — ready to convene.</>
        ) : (
          <>
            Drag cards onto the table — seat at least {MIN_SEATED} (of{" "}
            {SEAT_COUNT}) to begin.
          </>
        )}
      </div>

      <div className="rtable-tray" style={{ minHeight: `${Math.round(cardW * 0.94 * 1.6) + 22}px` }}>
        {tray.length === 0 && (
          <div className="tray-empty">Every character is at the table.</div>
        )}
        {tray.map((id, i) => {
          const def = defById.get(id);
          if (!def) return null;
          const w = trayCardW;
          const hidden = drag?.id === id || fly?.id === id;
          return (
            <div
              key={id}
              className={`rcard-holder tray-card${settleId === id ? " settle" : ""}${hidden ? " ghost-hidden" : ""}`}
              style={
                {
                  "--fan-rot": `${((i - fanMid) * 5).toFixed(2)}deg`,
                  "--fan-y": `${(Math.abs(i - fanMid) * 7).toFixed(1)}px`,
                  marginLeft: `${trayMargin}px`,
                  marginRight: `${trayMargin}px`,
                } as CSSProperties
              }
              ref={registerCard(id)}
              role="button"
              tabIndex={0}
              aria-label={`${def.name} — drag onto the table, or activate to seat`}
              onPointerDown={(e) => beginPress(e, id, -1)}
              onPointerMove={movePress}
              onPointerUp={(e) => endPress(e)}
              onPointerCancel={(e) => endPress(e, true)}
              onKeyDown={cardKeyToggle(id)}
            >
              <CharacterCard def={def} size={w} />
            </div>
          );
        })}
      </div>

      {drag && defById.get(drag.id) && (
        <div
          className="rcard-ghost"
          style={{
            left: `${drag.x - drag.dx}px`,
            top: `${drag.y - drag.dy}px`,
            width: `${drag.w}px`,
          }}
        >
          <CharacterCard def={defById.get(drag.id)!} size={Math.round(drag.w)} />
        </div>
      )}

      {fly && defById.get(fly.id) && (
        <div
          className={`rcard-fly${fly.phase === "go" ? " go" : ""}`}
          style={
            fly.phase === "go"
              ? { left: `${fly.tx}px`, top: `${fly.ty}px`, width: `${fly.tw}px` }
              : { left: `${fly.fx}px`, top: `${fly.fy}px`, width: `${fly.w}px` }
          }
          onTransitionEnd={(e) => {
            if (e.propertyName === "top" || e.propertyName === "left") {
              finishFly();
            }
          }}
        >
          <CharacterCard
            def={defById.get(fly.id)!}
            size={Math.round(fly.phase === "go" ? (fly.tw ?? fly.w) : fly.w)}
          />
        </div>
      )}
    </div>
  );
}
