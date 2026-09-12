// Roundtable — splash / landing page. The discussion app lives at /table.

import Link from "next/link";

export default function Splash() {
  return (
    <main className="splash">
      {/* Hero */}
      <section
        className="splash-hero"
        style={{ backgroundImage: "url(/splash/hero.jpg)" }}
      >
        <div className="splash-hero-veil">
          <h1>The Roundtable</h1>
          <p className="splash-tagline">
            A seminar table of AI minds — in your room on Apple&nbsp;Vision&nbsp;Pro,
            or right here in the browser.
          </p>
          <div className="splash-cta-row">
            <Link href="/table" className="splash-cta primary">
              Sit down at the table
            </Link>
            <Link href="/characters" className="splash-cta">
              Create a character
            </Link>
          </div>
        </div>
      </section>

      {/* What it is */}
      <section className="splash-intro">
        <p>
          Roundtable seats you at a Harkness table in an antique classroom with
          three to five AI characters who actually talk to each other — and to
          you. Pick a question or hand them a document, listen in, and
          interject out loud whenever you like. They hear you, answer you by
          name, and carry on.
        </p>
      </section>

      {/* How it works */}
      <section className="splash-steps">
        <article className="splash-step">
          <div className="splash-step-media">
            <img
              src="/splash/menu.jpg"
              alt="The Vision Pro menu: tonight's question, the cast, and session settings"
              loading="lazy"
            />
          </div>
          <div className="splash-step-text">
            <span className="splash-step-num">I</span>
            <h2>Pick a question, deal your cast</h2>
            <p>
              Choose tonight&rsquo;s question — or bring a PDF — then build the
              table. Every character is a tarot-style card: drag the ones you
              want onto the miniature table in the headset, or onto the felt
              right here on the web. A professor, a skeptic, a dreamer, a
              physicist, a historian… or anyone you&rsquo;ve invented.
            </p>
          </div>
        </article>

        <article className="splash-step reverse">
          <div className="splash-step-media">
            <img
              src="/splash/session.jpg"
              alt="Inside the immersive session: characters seated at the oak table, the topic chalked on the wall, live subtitles"
              loading="lazy"
            />
          </div>
          <div className="splash-step-text">
            <span className="splash-step-num">II</span>
            <h2>Take your seat</h2>
            <p>
              On Vision Pro the classroom surrounds you: lamplight, worn
              bookshelves, your question chalked on the wall, and the cast
              seated across the oak table — each with their own voice,
              lip-synced face, and opinions. Look at someone and start talking;
              they stop, listen, and answer. A green gem hovers over whoever
              holds the floor, and the sharpest ideas fly to your gem rack as
              collectible insights.
            </p>
          </div>
        </article>

        <article className="splash-step">
          <div className="splash-step-media">
            <img
              src="/splash/deck.jpg"
              alt="A live Vision Pro session: a deck page on the presentation board, page controls in hand, insight gems collected at the table edge"
              loading="lazy"
            />
          </div>
          <div className="splash-step-text">
            <span className="splash-step-num">III</span>
            <h2>Put a deck on the table</h2>
            <p>
              Upload a PDF — an investment deck, a paper, a proposal — and it
              goes up on the presentation board. The table discusses the page
              you&rsquo;re on as you flip, grounded in fresh context pulled
              from the web. Directed mode adds structure: set a goal and key
              points, and the moderator works through them, checks in with you
              at each one, and steers the table back when it drifts.
            </p>
          </div>
        </article>

        <article className="splash-step reverse">
          <div className="splash-step-media">
            <img
              src="/splash/cards.jpg"
              alt="Ornate tarot-style character cards fanned on a felt table"
              loading="lazy"
            />
          </div>
          <div className="splash-step-text">
            <span className="splash-step-num">IV</span>
            <h2>Mint your own minds</h2>
            <p>
              On the <Link href="/characters">Characters</Link> page, describe
              a personality — worldview, way of speaking, the hill they&rsquo;ll
              die on — pick a voice, and an oil-painted portrait is generated
              for their card. Your creations take a chair on the web and in the
              headset alike.
            </p>
          </div>
        </article>

        <article className="splash-step">
          <div className="splash-step-media phone">
            <img
              src="/splash/iphone.jpg"
              alt="The iPhone companion app: join the table over FaceTime"
              loading="lazy"
            />
          </div>
          <div className="splash-step-text">
            <span className="splash-step-num">V</span>
            <h2>Bring real people</h2>
            <p>
              Start a FaceTime call and share the session. A friend on another
              Vision Pro sits at the table as their Spatial Persona; iPhone
              guests join through the companion app and appear as their chosen
              character&rsquo;s card, glowing while they speak. Everyone can
              interject, and the characters answer each of you by name.
            </p>
          </div>
        </article>
      </section>

      {/* Closing CTA */}
      <section className="splash-final">
        <img
          src="/splash/gem.jpg"
          alt=""
          aria-hidden="true"
          className="splash-final-gem"
          loading="lazy"
        />
        <h2>The seminar is in session.</h2>
        <div className="splash-cta-row">
          <Link href="/table" className="splash-cta primary">
            Open the web roundtable
          </Link>
        </div>
        <p className="splash-fine">
          The web table runs in any modern browser. The full immersive
          experience is a Vision&nbsp;Pro app; iPhone companions join live
          sessions over FaceTime.
        </p>
      </section>
    </main>
  );
}
