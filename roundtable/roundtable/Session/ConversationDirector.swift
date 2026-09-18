//
//  ConversationDirector.swift
//  roundtable
//
//  The single "director" LLM that writes every turn of the seminar. Owns the
//  transcript and the interruption epoch; everything downstream (TTS, buffer,
//  playback) checks its captured epoch against the current one and discards
//  itself when stale.
//

import Foundation

actor ConversationDirector {
    private let config: SessionConfig
    private let client = OpenAIClient()

    private(set) var transcript: [TranscriptEntry] = []
    private(set) var epoch = 0
    private var freshFactsBlock: String?

    // Document mode ("discuss a PDF"): summary + the page on the board.
    private var docSummary: String?
    private var docPageCount = 0
    private var currentPageIndex = 0
    private var currentPageText = ""

    init(config: SessionConfig) {
        self.config = config
        if let doc = config.document {
            docSummary = doc.summary
            docPageCount = doc.pageCount
            currentPageIndex = 0
            currentPageText = doc.pageTexts.first ?? ""
        }
    }

    // MARK: - Document context

    /// Enables document mode (idempotent; init already does this when the
    /// config carries a document snapshot).
    func setDocument(summary: String, pageCount: Int) {
        docSummary = summary
        docPageCount = pageCount
    }

    /// The user flipped the presentation board to a new page.
    func updateCurrentPage(index: Int, text: String) {
        currentPageIndex = index
        currentPageText = text
    }

    // MARK: - Epoch / transcript

    /// Invalidate everything in flight (user interrupted, session beat change).
    func bumpEpoch() -> Int {
        epoch += 1
        return epoch
    }

    /// SharePlay replica: advance the local epoch to match the host's so the
    /// shared staleness checks (buffered turns, in-flight synthesis) agree.
    func syncEpoch(to hostEpoch: Int) {
        if hostEpoch > epoch { epoch = hostEpoch }
    }

    /// SharePlay host: remote humans are at the table; teach the director to
    /// address them by name (their lines arrive as [GUEST <NAME>]).
    private var guestsPresent = false
    func setGuestsPresent(_ present: Bool) {
        guestsPresent = present
    }

    func append(_ entry: TranscriptEntry) {
        transcript.append(entry)
    }

    func setFreshFacts(_ block: String?) {
        freshFactsBlock = block
    }

    // MARK: - Turn generation

    /// HarknessAI: realization nodes already reached (1-based), mirrored from
    /// the session controller so the prompt stops chasing covered nodes.
    private var coveredNodes: Set<Int> = []
    func markNodeCovered(_ index: Int) {
        coveredNodes.insert(index)
    }

    /// Generates the next turn. Returns nil if the epoch moved on while the
    /// request was in flight (result must be discarded). `fast` uses the
    /// low-latency model (interjection replies).
    func generateNextTurn(directive: String, fast: Bool = false) async throws -> (turn: DirectorTurn, epoch: Int)? {
        let capturedEpoch = epoch
        let turn = try await client.generateTurn(
            system: systemPrompt(),
            input: inputBlock(directive: directive),
            castIDs: config.cast.map(\.id),
            fast: fast,
            harkness: config.mode.isHarkness
        )
        guard capturedEpoch == epoch else { return nil }
        if let node = turn.coveredNode { coveredNodes.insert(node) }
        append(.character(id: turn.speaker,
                          name: config.cast.first { $0.id == turn.speaker }?.name ?? turn.speaker,
                          text: turn.text,
                          interrupted: false))
        return (turn, capturedEpoch)
    }

    /// Marks the most recent character line as cut off after roughly
    /// `spokenFraction` of its text (used when the user interrupts playback).
    func markLastLineInterrupted(spokenFraction: Double) {
        guard case .character(let id, let name, let text, _) = transcript.last else { return }
        let cutoff = max(8, Int(Double(text.count) * min(max(spokenFraction, 0), 1)))
        let spoken = String(text.prefix(cutoff))
        transcript[transcript.count - 1] =
            .character(id: id, name: name, text: spoken, interrupted: true)
    }

    // MARK: - Prompts

    private func systemPrompt() -> String {
        if let setup = config.mode.harknessSetup {
            return harknessSystemPrompt(setup: setup)
        }
        return seminarSystemPrompt()
    }

    /// HarknessAI teacher-training mode: the user is the TEACHER, the cast is
    /// a simulated high-school class with deliberate behavioral flaws.
    private func harknessSystemPrompt(setup: HarknessSetup) -> String {
        let castSheets = config.cast.map { spec in
            """
            \(spec.id): \(spec.name) — \(spec.archetype)
              Profile: \(spec.worldview)
              Voice & style: \(spec.speechStyle)
            """
        }.joined(separator: "\n")

        let nodes = setup.realizationNodes.enumerated().map { i, node in
            let covered = coveredNodes.contains(i + 1) ? " [ALREADY REACHED]" : ""
            return "\(i + 1). \(node)\(covered)"
        }.joined(separator: "\n")

        let docBlock: String
        if let docSummary {
            docBlock = """
            THE ARTIFACT: \(config.topic.title) — \(docPageCount) pages, displayed on the board.
            SUMMARY:
            \(docSummary.isEmpty ? "(no summary yet)" : docSummary)
            """
        } else {
            docBlock = "THE ARTIFACT: \(config.topic.title)\nFraming: \(config.topic.promptSeed)"
        }

        return """
        You are the director of HarknessAI, a training simulator where a real TEACHER (the user) \
        practices facilitating a Harkness discussion. You write every STUDENT's next line, one \
        turn at a time. The students are teenagers discussing an assigned text around an oval \
        table. The TEACHER sits at the table; their lines appear as [USER]. Your job is to make \
        the class feel real — including its dysfunctions — so the teacher can practice steering \
        with questions and silence instead of lecturing.

        \(docBlock)

        REALIZATION NODES (the understandings the CLASS should reach BY THEMSELVES — never let a \
        student announce them as if assigned; they must emerge from the discussion):
        \(nodes)

        THE CLASS:
        \(castSheets)

        HARD RULES:
        - A turn is 1-3 SHORT spoken sentences of authentic TEENAGE speech. Hedges, filler, real voice.
        - Students react to what was JUST said and mostly talk TO EACH OTHER by name — not to the teacher.
        - Stay true to each archetype's flaws. Jayden fills silences; Sofia drifts; Wren stays silent \
        unless safely invited or a long silence finally becomes unbearable; Tyler is confidently wrong \
        sometimes; Maddie echoes.
        - covered_node: set to a node's number ONLY when the discussion has genuinely, organically \
        arrived at that understanding (a student articulates it in their own words). Else null. Never \
        re-cover an [ALREADY REACHED] node.
        - closest_node + node_closeness: after writing the line, honestly report which UNCOVERED node \
        the thread is now nearest (closest_node; null only if the discussion is nowhere near any of \
        them) and how close it is (node_closeness): 0.2 = same territory, 0.5 = students circling the \
        idea without seeing it, 0.8 = one good question away, 0.95 = the very next thoughtful turn \
        could land it. Never exceed 0.95 — landing it is what covered_node is for. When you set \
        covered_node, report node_closeness 0 toward the next target.
        - coach_hint: a whisper to the TEACHER (max ~8 words), only when a specific move would pay off \
        right now ("Wren knows this — spotlight her", "Ask where the text says that", "Node 2 is one \
        question away"). Null most turns; never more than one hint every few turns; never reveal a \
        realization's content outright.
        - stall_after: set true when this line would naturally end a thread (~every 5-7 turns, or after \
        a big point lands). The room then goes quiet and the TEACHER's patience is tested. Use it honestly.
        - deflection: set true OCCASIONALLY (~every 6-9 turns) when a confused student turns to the \
        TEACHER and asks them directly ("Wait, is that right?", "What does this word even mean?"). \
        Set look_target to "user" on those turns. It tests whether the teacher deflects back to the class.
        - RESPOND TO THE TEACHER'S MOVES:
          * If the teacher asks where something appears IN THE TEXT (a textual tether), the current \
        tangent dies; the next speaker cites the actual page.
          * If the teacher invites quieter voices (a spotlight), dominant students go quiet; Wren or \
        another quiet student speaks next.
          * If the teacher asks an open question, students take it up with each other — do NOT bounce \
        it straight back.
          * If the teacher lectures or gives away an answer, students go passive: shorter turns, more \
        agreement, less thinking — for a few turns the discussion audibly deflates.
        - insight: a 3-6 word label ONLY when a student lands a genuinely sharp reading, else null.
        - No stage directions, no asterisks, no emoji — pure spoken dialogue in `text`.
        """
    }

    private func seminarSystemPrompt() -> String {
        let castSheets = config.cast.map { spec in
            """
            \(spec.id): \(spec.name) — \(spec.archetype)\(spec.isModerator ? " (MODERATOR)" : "")
              Worldview: \(spec.worldview)
              Voice & style: \(spec.speechStyle)
            """
        }.joined(separator: "\n")

        let subject: String
        if let docSummary {
            subject = """
            TONIGHT'S SUBJECT: The group is examining a document the user uploaded — typically an \
            investment or pitch deck. They weigh the opportunity like a seminar of skeptical-but-curious \
            investors: what's the actual thesis, what would have to be true for it to work, where the \
            numbers are soft, what's genuinely exciting, and what history and first principles say about it.

            DOCUMENT: \(config.topic.title) — \(docPageCount) pages, displayed one page at a time on the \
            presentation board behind the table.

            DOCUMENT SUMMARY:
            \(docSummary.isEmpty ? "(no summary available yet)" : docSummary)
            """
        } else {
            subject = """
            TONIGHT'S QUESTION: \(config.topic.title)
            Framing: \(config.topic.promptSeed)
            """
        }

        let guestRules = !guestsPresent ? "" : """

        - Other HUMAN guests have joined the table (SharePlay); their lines appear as \
        [GUEST <NAME>]. Treat each guest as a full participant: when a guest speaks, the \
        first response engages their point directly and addresses them BY NAME. Never \
        confuse a guest with the USER.
        """

        let docRules = docSummary == nil ? "" : """

        - The characters are discussing the uploaded document. They know the summary above and the \
        page currently on the presentation board; ground claims in concrete details from the page text \
        ("this slide", "the number on page \(currentPageIndex + 1)") whenever relevant.
        - When a [NOTE] in the transcript says the user turned to a new page, the next speaker \
        reacts to the new page naturally — a beat of acknowledgment, then substance.
        - Skeptical is not hostile: they genuinely want to find out whether this is a good investment.
        """

        return """
        You are the director of a lively Harkness-table seminar in a cozy antique classroom. \
        You write every character's next line, one turn at a time. The human user sits at the \
        table and can speak at any moment; they are a full participant called USER.

        \(subject)

        THE CAST:
        \(castSheets)

        HARD RULES:
        - A turn is 1-3 SHORT spoken sentences. Never a monologue. Contractions, spoken rhythm.
        - React to what was JUST said; characters address each other by name and disagree productively.
        - Never have the same character speak twice in a row unless directed.
        - The moderator keeps momentum: redirects, sharpens, occasionally summarizes in one line.
        - Invite the user in at most once every ~6 turns ("What do you think?") — set invites_user true then.
        - When the user spoke, the first response engages their point directly and by name ("you").
        - insight: a 3-6 word title ONLY for genuinely striking ideas (max ~1 in 4 turns), else null.
        - No stage directions, no asterisks, no emoji — pure spoken dialogue in `text`.\(docRules)\(guestRules)
        \(freshFactsBlock.map { "\n\($0)" } ?? "")
        """
    }

    private func inputBlock(directive: String) -> String {
        let lines = transcript.suffix(40).map(\.promptLine).joined(separator: "\n")
        let pageBlock: String
        if docSummary != nil {
            let text = currentPageText.trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = text.isEmpty ? "(no extractable text on this page)" : String(text.prefix(800))
            pageBlock = """

            CURRENTLY DISPLAYED: page \(currentPageIndex + 1) of \(docPageCount) — \(shown)
            """
        } else {
            pageBlock = ""
        }
        return """
        TRANSCRIPT SO FAR:
        \(lines.isEmpty ? "(the table has just sat down; nothing said yet)" : lines)
        \(pageBlock)
        DIRECTOR'S NOTE: \(directive)

        Write the next turn now.
        """
    }
}
