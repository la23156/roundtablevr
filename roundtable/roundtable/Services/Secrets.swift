//
//  Secrets.swift
//  roundtable
//
//  API keys come from Secrets.plist, which is gitignored and bundled only in
//  this personal dev build. A shipped app would proxy these calls instead.
//

import Foundation

enum Secrets {
    private static let values: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: String] else {
            assertionFailure("Secrets.plist missing from bundle")
            return [:]
        }
        return dict
    }()

    static var openRouterKey: String { values["OPENROUTER_API_KEY"] ?? "" }
    static var deepgramKey: String { values["DEEPGRAM_API_KEY"] ?? "" }
    static var exaKey: String { values["EXA_API_KEY"] ?? "" }
}
