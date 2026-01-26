//
//  SummaryExportView.swift
//  TwistTally
//
//  Results UI (formerly “Summary & Export”)
//  - Shows each contest name + a top-5 leaderboard
//  - Exports:
//      1) Share Results as PDF (organizer-friendly)
//      2) Export All Results as CSV (all entrants, grouped by contest)
//
//  NOTE: It’s totally fine to rename this file to ResultsView.swift in Xcode.
//

import SwiftUI
import UIKit

// MARK: - Public Results Screen

struct ResultsView: View {
    @ObservedObject var store: TallyStore

    @Environment(\.dismiss) private var dismiss

    // User feedback (shown AFTER the share sheet closes)
    @State private var statusMessage: String? = nil

    // Timestamp captured per export (also used in the PDF footer)
    @State private var lastExportTimestamp: String = ExportUtil.timestamp()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {

                // Buttons ABOVE the title
                exportButtons

                Text("Contest Results")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                resultsList
            }
            .padding(.top, 8)
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .top) {
                if let msg = statusMessage {
                    ResultsStatusBanner(message: msg)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: statusMessage)
        }
    }

    // MARK: - UI pieces

    private var exportButtons: some View {
        HStack(spacing: 12) {
            Button {
                exportPDF()
            } label: {
                Label("Share Results (PDF)", systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("BrandAccentStrong"))

            Button {
                exportCSV()
            } label: {
                Label("Export All (CSV)", systemImage: "tablecells")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
    }

    private var resultsList: some View {
        List {
            if store.contests.isEmpty {
                ContentUnavailableView(
                    "No contests",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Create a contest and start tallying.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.contests) { contest in
                    Section {
                        ResultsLeaderboard(contest: contest)
                    } header: {
                        Text(contest.name)
                            .font(.headline)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Export actions

    @MainActor
    private func presentShare(for url: URL) {
        // Defensive: ensure file exists and is non-empty before presenting.
        let maxAttempts = 30
        var isReady = false
        for _ in 0..<maxAttempts {
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue,
               size > 0 {
                isReady = true
                break
            }
            // Small delay (20ms) to allow the write to flush.
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        guard isReady else {
            showStatus("Couldn’t prepare share sheet")
            return
        }

        ShareUtil.present(url: url) { completed, error in
            // Called when the user dismisses the share sheet.
            if let error {
                showStatus("Couldn’t share: \(error.localizedDescription)")
            } else if completed {
                showStatus("Shared ✅")
            } else {
                showStatus("Share canceled")
            }
        }
    }

    private func exportCSV() {
        lastExportTimestamp = ExportUtil.timestamp()

        let csv = CSVExporter.makeFullScoresCSV(contests: store.contests)
        let title = "TwistTally_AllScores_\(lastExportTimestamp)"

        guard let url = FileUtil.writeTempFile(
            fileName: "\(title).csv",
            data: Data(csv.utf8)
        ) else {
            showStatus("Couldn’t create CSV")
            return
        }

        presentShare(for: url)
    }

    private func exportPDF() {
        lastExportTimestamp = ExportUtil.timestamp()

        let pdfView = ResultsPDFView(
            contests: store.contests,
            talliedOn: lastExportTimestamp
        )

        let title = "TwistTally_Results_\(lastExportTimestamp)"

        guard let url = PDFExporter.makePDF(
            title: title,
            view: pdfView,
            pageWidth: 1024
        ) else {
            showStatus("Couldn’t create PDF")
            return
        }

        presentShare(for: url)
    }

    private func showStatus(_ message: String) {
        statusMessage = message

        // Keep it on-screen long enough that it’s visible after the share sheet closes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }
}

// MARK: - Leaderboard cell

private struct ResultsLeaderboard: View {
    let contest: Contest

    private var topFive: [Entrant] {
        contest.entrants
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if topFive.isEmpty {
                Text("No entrants")
                    .foregroundStyle(.secondary)
            } else if topFive.allSatisfy({ $0.score == 0 }) {
                Text("No scores yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(topFive.enumerated()), id: \.element.id) { rank, entrant in
                    HStack {
                        Text("#\(rank + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)

                        Text(entrant.name)
                            .lineLimit(1)

                        Spacer()

                        Text("\(entrant.score)")
                            .font(.headline)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - PDF content view (rendered into the PDF)

private struct ResultsPDFView: View {
    let contests: [Contest]
    let talliedOn: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Contest Results")
                .font(.largeTitle)
                .fontWeight(.bold)

            ForEach(contests) { contest in
                VStack(alignment: .leading, spacing: 8) {
                    Text(contest.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    let topFive = contest.entrants
                        .sorted { a, b in
                            if a.score != b.score { return a.score > b.score }
                            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                        }
                        .prefix(5)

                    if topFive.isEmpty {
                        Text("No entrants")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(topFive.enumerated()), id: \.element.id) { rank, entrant in
                            HStack {
                                Text("#\(rank + 1)")
                                    .frame(width: 40, alignment: .leading)
                                    .foregroundStyle(.secondary)

                                Text(entrant.name)
                                Spacer()
                                Text("\(entrant.score)")
                                    .monospacedDigit()
                            }
                            .font(.body)
                        }
                    }
                }
                .padding(.top, 8)

                Divider()
            }

            Spacer(minLength: 24)

            Text("Tallied on \(talliedOn)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - UIKit share presenter

private enum ShareUtil {
    @MainActor
    static func present(url: URL, onComplete: @escaping (_ completed: Bool, _ error: Error?) -> Void) {
        guard let topVC = topViewController() else {
            onComplete(false, NSError(domain: "TwistTally", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active view controller"]))
            return
        }

        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.completionWithItemsHandler = { _, completed, _, error in
            onComplete(completed, error)
        }

        if let pop = activity.popoverPresentationController {
            pop.sourceView = topVC.view
            pop.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }

        topVC.present(activity, animated: true)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        let keyWindow = scenes
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })

        guard var top = keyWindow?.rootViewController else { return nil }

        while let presented = top.presentedViewController {
            top = presented
        }

        if let nav = top as? UINavigationController {
            return nav.visibleViewController ?? nav
        }
        if let tab = top as? UITabBarController {
            return tab.selectedViewController ?? tab
        }

        return top
    }
}

// MARK: - Simple status banner

private struct ResultsStatusBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 1))
            .shadow(radius: 4)
    }
}

// MARK: - Temp file helper

private enum FileUtil {
    static func writeTempFile(fileName: String, data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
