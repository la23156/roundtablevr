//
//  DiscussionDocument.swift
//  roundtable
//
//  A PDF the table discusses. The live class (PDFKit document + current page)
//  stays on AppModel/SessionController; the value-type info snapshot travels
//  inside SessionConfig so the config stays a plain value.
//

import Foundation
import Observation
import PDFKit
import UIKit

/// Value-type snapshot of the document that rides along in SessionConfig.
struct DiscussionDocumentInfo: Equatable {
    var title: String
    var summary: String
    var entities: [String]
    var pageTexts: [String]

    var pageCount: Int { pageTexts.count }
}

/// The live document: PDFKit handle, extracted per-page text, async-filled
/// summary, and the page currently on the presentation board.
@MainActor
@Observable
final class DiscussionDocument {
    @ObservationIgnored let pdf: PDFDocument
    let title: String
    /// Extracted text per page (empty string where extraction fails).
    let pageTexts: [String]
    /// Filled asynchronously by OpenAIClient.summarizeDocument.
    var docSummary: String = ""
    var entities: [String] = []
    var currentPageIndex: Int = 0

    var pageCount: Int { pdf.pageCount }

    init?(data: Data, title: String) {
        guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else { return nil }
        self.pdf = pdf
        self.title = title
        self.pageTexts = (0..<pdf.pageCount).map { pdf.page(at: $0)?.string ?? "" }
    }

    convenience init?(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data, title: url.deletingPathExtension().lastPathComponent)
    }

    /// Full extracted text with page markers, for the summarizer.
    var fullText: String {
        pageTexts.enumerated()
            .map { "— Page \($0.offset + 1) —\n\($0.element)" }
            .joined(separator: "\n\n")
    }

    /// Snapshot for SessionConfig (call after the summary has been filled).
    var info: DiscussionDocumentInfo {
        DiscussionDocumentInfo(title: title, summary: docSummary, entities: entities, pageTexts: pageTexts)
    }

    /// Renders page `index` at roughly `width` points wide for the board.
    func pageImage(_ index: Int, width: CGFloat) -> CGImage? {
        guard let page = pdf.page(at: index) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let size = CGSize(width: width, height: width * bounds.height / bounds.width)
        return page.thumbnail(of: size, for: .mediaBox).cgImage
    }
}
