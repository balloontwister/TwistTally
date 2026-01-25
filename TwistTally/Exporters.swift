//
//  Exporters.swift
//  TwistTally
//
//  Created by Todd Neufeld on 1/25/26.
//

import Foundation
import UIKit
import SwiftUI


// MARK: - Export Utilities

enum ExportUtil {
    static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        return f.string(from: Date())
    }

    /// Makes a string safe for use in filenames (no slashes/colons, trims whitespace).
    static func safeFileComponent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Export" }

        // Replace common filename-hostile characters with underscores.
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let parts = trimmed.components(separatedBy: unsafe)
        let joined = parts.joined(separator: "_")

        // Collapse repeated underscores.
        var out = joined.replacingOccurrences(of: " ", with: "_")
        while out.contains("__") {
            out = out.replacingOccurrences(of: "__", with: "_")
        }
        return out
    }

    static func csvFileName(prefix: String = "TwistTally_AllScores") -> String {
        "\(safeFileComponent(prefix))_\(timestamp()).csv"
    }

    static func pdfFileName(title: String) -> String {
        "\(safeFileComponent(title))_\(timestamp()).pdf"
    }
}

// MARK: - CSV Export

enum CSVExporter {
    /// CSV grouped by contest.
    /// - Contests are grouped (one block per contest).
    /// - Within each contest, entrants are sorted by score descending (ties: name ascending).
    static func makeGroupedScoresCSV(contests: [Contest]) -> String {
        // Header row
        var rows: [String] = [
            #"Contest,Entrant,Score"#
        ]

        // Stable ordering: contests by name
        let sortedContests = contests.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        for contest in sortedContests {
            // Sort entrants within contest
            let sortedEntrants = contest.entrants.sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            for entrant in sortedEntrants {
                rows.append("\(escapeCSV(contest.name)),\(escapeCSV(entrant.name)),\(entrant.score)")
            }
        }

        return rows.joined(separator: "\n")
    }

    /// One row per entrant across all contests, sorted by score desc (ties: contest, name).
    static func makeFullScoresCSV(contests: [Contest]) -> String {
        // Header row
        var rows: [String] = [
            #"Contest,Entrant,Score"#
        ]

        // Flatten all contests/entrants into rows
        let all = contests.flatMap { contest in
            contest.entrants.map { entrant in
                (contest: contest.name, name: entrant.name, score: entrant.score)
            }
        }

        // Sort: score desc, then contest name, then entrant name
        let sorted = all.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.contest != $1.contest { return $0.contest < $1.contest }
            return $0.name < $1.name
        }

        for item in sorted {
            rows.append("\(escapeCSV(item.contest)),\(escapeCSV(item.name)),\(item.score)")
        }

        return rows.joined(separator: "\n")
    }

    private static func escapeCSV(_ s: String) -> String {
        // Quote fields that contain commas, quotes, or newlines
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            let doubled = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(doubled)\""
        }
        return s
    }
}

// MARK: - PDF Export (renders any SwiftUI view into a single-page PDF sized to iPad width)

enum PDFExporter {
    /// Renders a SwiftUI view into a PDF. Best for “Summary” exports.
    /// Note: This makes a single long page PDF (scroll-like). Great for sharing.
    static func makePDF<V: View>(
        title: String,
        view: V,
        pageWidth: CGFloat = 1024 // iPad-ish width
    ) -> URL? {
        // Build a hosting controller to render the SwiftUI view
        let controller = UIHostingController(rootView: view)
        controller.view.backgroundColor = .clear

        // Force layout at a known width; height expands to fit content
        let targetSize = controller.sizeThatFits(in: CGSize(width: pageWidth, height: .greatestFiniteMagnitude))
        controller.view.bounds = CGRect(origin: .zero, size: targetSize)
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: targetSize))

        // Write PDF to temp URL
        let filename = ExportUtil.pdfFileName(title: title)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            return url
        } catch {
            return nil
        }
    }
}
