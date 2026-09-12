//
//  CharacterStore.swift
//  roundtable
//
//  Merges the built-in cast with characters created on the website
//  (GET https://roundtable.spmhresearch.org/api/characters). Cached in
//  UserDefaults so the cast table works offline; refreshes on menu load.
//

import Foundation
import Observation
import SwiftUI

/// Wire format shared with the web platform (lib/characterTypes.ts).
struct RemoteCharacterDef: Codable {
    let id: String
    let name: String
    let archetype: String
    let bio: String
    let worldview: String
    let speechStyle: String
    let voiceID: String
    let tintHex: String
    let baseBody: String
    let portraitURL: String?
    let builtIn: Bool?
    let isModerator: Bool?
}

@MainActor
@Observable
final class CharacterStore {
    private static let cacheKey = "remoteCharacters.v1"
    private static let endpoint = URL(string: "https://roundtable.spmhresearch.org/api/characters")!

    /// Web-created characters as CharacterSpec (excludes built-ins, which the
    /// app defines locally with bundled portraits).
    private(set) var customs: [CharacterSpec] = []
    /// Custom-id -> remote portrait URL (built-ins use bundled art).
    private(set) var portraitURLs: [String: URL] = [:]

    var all: [CharacterSpec] { CharacterRoster.all + customs }

    func spec(for id: String) -> CharacterSpec? {
        all.first { $0.id == id }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let defs = try? JSONDecoder().decode([RemoteCharacterDef].self, from: data) {
            apply(defs)
        }
    }

    private struct Envelope: Codable {
        let characters: [RemoteCharacterDef]
    }

    func refresh() async {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let defs = try? JSONDecoder().decode(Envelope.self, from: data).characters else {
            print("CharacterStore: refresh failed (offline? platform down?) — using cache")
            return
        }
        let customDefs = defs.filter { $0.builtIn != true }
        UserDefaults.standard.set(try? JSONEncoder().encode(customDefs), forKey: Self.cacheKey)
        apply(customDefs)
        print("CharacterStore: \(customs.count) custom character(s) from platform")
    }

    private func apply(_ defs: [RemoteCharacterDef]) {
        let validBodies = Set(CharacterRoster.all.map(\.avatarAssetName))
        customs = defs.compactMap { def in
            guard !CharacterRoster.all.contains(where: { $0.id == def.id }) else { return nil }
            if let urlString = def.portraitURL, let url = URL(string: urlString), url.scheme != nil {
                portraitURLs[def.id] = url
            }
            return CharacterSpec(
                id: def.id,
                name: def.name,
                archetype: def.archetype,
                bio: def.bio,
                worldview: def.worldview,
                speechStyle: def.speechStyle,
                isModerator: false,                       // customs never moderate
                voiceID: def.voiceID,
                avatarAssetName: validBodies.contains(def.baseBody) ? def.baseBody : "preview",
                tint: Color(hex: def.tintHex) ?? .brown
            )
        }
    }
}

extension Color {
    /// "#RRGGBB" / "RRGGBB" parser for platform tints.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
