// HarknessAI — teacher-training brand landing (served as the root of
// harknessai.com via middleware; also reachable at /harkness).

import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "HarknessAI — a flight simulator for teachers",
  description:
    "Practice guiding a Harkness discussion against a simulated class of AI students — a Monopolizer, a Tangent Weaver, a silent Ghost — using only questions and silence. On Apple Vision Pro.",
  openGraph: {
    title: "HarknessAI",
    description:
      "A flight simulator for teachers: guide a simulated Harkness discussion using only questions and silence.",
    url: "https://harknessai.com",
    siteName: "HarknessAI",
    type: "website",
  },
};

const ARCHETYPES = [
  {
    name: "The Monopolizer",
    student: "Jayden",
    blurb:
      "Always first to speak, never deeper than the surface. Thinks filling the silence is helping. Your spotlight is the counter.",
  },
  {
    name: "The Tangent Weaver",
    student: "Sofia",
    blurb:
      "Hyper-fixates on a minor detail or drifts into a personal story. One question kills it: “Where do you see that in the text?”",
  },
  {
    name: "The Ghost",
    student: "Wren",
    blurb:
      "Understands everything. Says nothing — unless you make it safe, or a silence stretches long enough that she finally risks it.",
  },
  {
    name: "The Confidently Incorrect",
    student: "Tyler",
    blurb:
      "Makes a bold, wrong claim and sells it hard. Resist correcting him yourself — the table has to do it with the text.",
  },
  {
    name: "The Echo",
    student: "Maddie",
    blurb:
      "Restates whoever spoke last, sincerely, as a brand-new idea. Can you turn repetition into a real position?",
  },
];

const MECHANICS = [
  {
    title: "The Silence Tension Meter",
    body: "When the thread dies, the room goes silent and a tension bar starts filling at the edge of your vision. Speak too soon and you “rescued” the class — the bar resets and it counts against you. Hold out until it fills, and the discomfort forces a student to take ownership of the lull. Sometimes it's the Ghost.",
  },
  {
    title: "Gaze-tracked deflections",
    body: "A confused student will look you dead in the eye and ask, “Wait — is that right?” Answer them and the HUD flashes a Lecturing Penalty. Turn your head to another student and hand the question back — “I don't know, what does the table think?” — and you pass the test.",
  },
  {
    title: "Voice-recognized interventions",
    body: "The simulator listens to every intervention and scores the move: a textual tether (“where do you see that in the text?”) cuts tangents and sends every head down to the page; a spotlight (“let's hear from someone who hasn't spoken”) quiets the dominant voices; a lecture audibly deflates the room.",
  },
  {
    title: "The Conversation Web",
    body: "Glowing lines on the tabletop trace who is talking to whom. Student-to-student chords glow blue; every time the flow bounces through you, the strand burns red. A starburst centered on the teacher is the pattern you're training out of.",
  },
  {
    title: "The Guideflow Tracker",
    body: "Your 3–5 realization nodes float as dim orbs above the table. When the class argues its way into one — in their own words, unprompted — the orb swells and turns gold.",
  },
];

export default function HarknessLanding() {
  return (
    <main className="splash">
      <section
        className="splash-hero"
        style={{ backgroundImage: "url(/harkness/hero.jpg)" }}
      >
        <div className="splash-hero-veil">
          <h1>HarknessAI</h1>
          <p className="splash-tagline">
            A flight simulator for teachers. Practice guiding a Harkness
            discussion against a class that talks back — using only your
            questions, your gaze, and your patience.
          </p>
          <div className="splash-cta-row">
            <a href="#how" className="splash-cta primary">
              How it works
            </a>
            <Link href="/table" className="splash-cta">
              Try the web roundtable
            </Link>
          </div>
        </div>
      </section>

      <section className="splash-intro">
        <p>
          The hardest skill in Harkness teaching is doing less: biting your
          tongue through a silence, deflecting the question you could answer in
          five seconds, letting a wrong claim stand until a student dismantles
          it. HarknessAI is a safe sandbox on Apple&nbsp;Vision&nbsp;Pro where
          you practice exactly that — against eight AI students engineered to
          test you.
        </p>
      </section>

      <section className="splash-steps" id="how">
        <article className="splash-step">
          <div className="splash-step-text">
            <span className="splash-step-num">SETUP</span>
            <h2>Upload the artifact, set the guideflow</h2>
            <p>
              Drop in the reading, historical document, or case study. The
              simulator digests its themes, evidence, and ambiguities — then
              you define 3–5 <em>realization nodes</em>: the understandings
              your class should reach by the end, on their own. Eight students
              take their seats around the oval table, each with their own
              reading level and personality.
            </p>
          </div>
          <div className="splash-step-media">
            <div className="hk-panel">
              {ARCHETYPES.map((a) => (
                <div key={a.name} className="hk-archetype">
                  <div className="hk-archetype-name">
                    {a.name} <span>· {a.student}</span>
                  </div>
                  <p>{a.blurb}</p>
                </div>
              ))}
            </div>
          </div>
        </article>

        <article className="splash-step reverse">
          <div className="splash-step-text">
            <span className="splash-step-num">PLAY</span>
            <h2>Your controls: voice, gaze, patience</h2>
            <p>
              There are no buttons in the room. The simulation reads the three
              instruments a real Harkness teacher has — what you say, where you
              look, and how long you can stand the silence — and the class
              responds the way teenagers actually do.
            </p>
          </div>
          <div className="splash-step-media">
            <div className="hk-panel">
              {MECHANICS.map((m) => (
                <div key={m.title} className="hk-archetype">
                  <div className="hk-archetype-name">{m.title}</div>
                  <p>{m.body}</p>
                </div>
              ))}
            </div>
          </div>
        </article>

      </section>

      {/* Inside the simulator: real captures + live mechanics */}
      <section className="splash-intro" id="inside">
        <p style={{ fontFamily: "var(--serif)" }}>
          <strong>Inside the simulator</strong> — captured from the app.
        </p>
      </section>
      <section className="hk-gallery">
        <figure className="hk-shot wide">
          <img
            src="/harkness/training.gif"
            alt="A live training session: students debating around the table with subtitles"
            loading="lazy"
          />
          <figcaption>
            A live session: eight students argue an uploaded text among
            themselves — subtitles, gazes, and the speaking gem move with the
            conversation while the teacher holds their tongue.
          </figcaption>
        </figure>

        <figure className="hk-shot">
          <img
            src="/harkness/web_orbs.jpg"
            alt="The conversation web glowing on the tabletop and guideflow orbs above it"
            loading="lazy"
          />
          <figcaption>
            The Conversation Web on the tabletop — blue chords are
            student-to-student; the red strand is the flow bouncing through
            the teacher. Above it, the Guideflow orbs wait to turn gold.
          </figcaption>
        </figure>

        <figure className="hk-shot">
          <img
            src="/harkness/classroom.jpg"
            alt="The decorated classroom: students in distinct shirts, framed paintings, the artifact on the board"
            loading="lazy"
          />
          <figcaption>
            The class in session: the artifact up on the board, every student
            a distinct voice, body, and shirt — and a distinct set of flaws.
          </figcaption>
        </figure>

        {/* Live mechanics, rebuilt in CSS so they move. */}
        <figure className="hk-shot">
          <div className="hk-crib">
            <div className="hk-crib-title">Your crib sheet — on the table, tilted toward you</div>
            <div className="hk-note hit">
              <span className="hk-note-num">1</span>
              <span className="hk-note-label struck">Moat is regulatory, not technical</span>
              <span className="hk-note-check">✓ +100</span>
            </div>
            <div className="hk-note pulsing">
              <span className="hk-note-num">2</span>
              <span className="hk-note-label">Projections assume nonexistent customer</span>
              <span className="hk-note-closing">closing in…</span>
            </div>
            <div className="hk-note">
              <span className="hk-note-num">3</span>
              <span className="hk-note-label">Team slide beats product slide</span>
            </div>
          </div>
          <figcaption>
            The realization nodes, condensed to glanceable labels. A note
            pulses amber as the discussion closes in on it; when a student
            lands it, it flashes green, gets struck out, and you score.
          </figcaption>
        </figure>

        <figure className="hk-shot">
          <div className="hk-crib">
            <div className="hk-crib-title">The Silence Tension Meter</div>
            <div className="hk-tension">
              <div className="hk-tension-bar" />
            </div>
            <div className="hk-tension-caption">
              the room is silent — hold it…
            </div>
            <div className="hk-hud-line">
              <span className="hk-score">★ 240</span>
              <span className="hk-flash good">Silence held +40 — a student steps up</span>
            </div>
            <div className="hk-hud-line">
              <span className="hk-hint">💡 Wren knows this — spotlight her</span>
            </div>
          </div>
          <figcaption>
            When a thread dies, the bar fills. Speak too soon and you rescued
            them (−20); outlast it and a student takes ownership (+40). The
            HUD keeps score and occasionally whispers a coaching hint.
          </figcaption>
        </figure>
      </section>

      <section className="splash-steps">
        <article className="splash-step">
          <div className="splash-step-text">
            <span className="splash-step-num">DEBRIEF</span>
            <h2>The numbers don&rsquo;t flatter</h2>
            <p>
              When class ends, the room fades to your analytics: a talk-time
              ratio (masters stay under 10–15%), every intervention replayed
              and classified — question or giveaway — silences held versus
              silences rescued, lecturing penalties, and table equity: did you
              manage the Monopolizer? Did the Ghost ever speak? Which
              realization nodes did the class actually reach?
            </p>
          </div>
          <div className="splash-step-media">
            <img
              src="/splash/session.jpg"
              alt="Inside the simulator: the class seated at the oval table in the antique classroom"
              loading="lazy"
            />
          </div>
        </article>
      </section>

      <section className="splash-final">
        <h2>Practice the hardest move in teaching: saying nothing.</h2>
        <p className="splash-fine">
          HarknessAI is a training mode of the Roundtable app for
          Apple&nbsp;Vision&nbsp;Pro. The same table also hosts open seminars
          with AI characters — and real colleagues over FaceTime — at{" "}
          <Link href="/">roundtable.spmhresearch.org</Link>.
        </p>
      </section>
    </main>
  );
}
