//
//  ContentView.swift
//  TwistTally
//
//  Created by Todd Neufeld on 1/24/26.
//

import SwiftUI
import UIKit
import Combine
import UniformTypeIdentifiers

struct ContentView: View {

    // MARK: - Store
    @StateObject private var store = TallyStore()

    // MARK: - UI State
    @State private var isShowingEditEntrants = false
    @State private var isShowingManage = false

    // Results & Export sheet
    @State private var isShowingSummaryExport = false

    // MARK: - Grid Layout
    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 120), spacing: 12)
    ]

    // MARK: - Per-contest accent (drives “we switched contests” feel)
    private var contestAccent: Color {
        guard let idx = store.currentContestIndex else { return Color("BrandAccent") }
        return Color(hex: store.contests[idx].accentHex)
    }

    private var currentEntrants: [Entrant] {
        guard let idx = store.currentContestIndex else { return [] }
        return store.contests[idx].entrants
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            mainLayout
                .toolbar { appTitleToolbar }

                // Persist contest selection changes (keeps save logic consistent)
                .onChange(of: store.selectedContestID) { _, _ in
                    store.selectionChanged()
                }

                // Undo confirmation banner
                .overlay(alignment: .top) { bannerOverlay }
                .animation(.easeInOut(duration: 0.2), value: store.bannerMessage)

                // Sheets
                .sheet(isPresented: $isShowingEditEntrants) { editEntrantsSheet }

                // Results & Export sheet
                .sheet(isPresented: $isShowingSummaryExport) {
                    ResultsExportView(store: store)
                }
        }
    }

    // MARK: - Toolbar (logo + app title stays flush-left)
    private var appTitleToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 8) {
                Image("inline-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 24)

                Text("Twist & Tally")
                    .font(.headline)
            }
        }
    }

    // MARK: - Main Layout
    private var mainLayout: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            mainContent
        }
    }

    // MARK: - Top Bar
    // ✅ Undo flush-left
    // ✅ Contest name centered
    // ✅ Top 5 strip centered below contest name
    // ✅ Manage flush-right (popover)
    private var topBar: some View {
        ZStack(alignment: .top) {

            // CENTER: contest name + top five
            VStack(spacing: 14) {

                if let idx = store.currentContestIndex {
                    Text(store.contests[idx].name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(contestAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.bottom, 4)
                        .padding(.horizontal, 80)
                }

                TopFiveStrip(
                    entrants: currentEntrants,
                    accent: contestAccent,
                    onTapEntrant: { id in
                        store.increment(entrantID: id)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
                .padding(.top, 6)
            }
            .padding(.top, 38) // reserves space for Undo/Manage row

            // LEFT + RIGHT overlay
            HStack {
                Button(action: store.undoLast) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("BrandAccentStrong"))
                .controlSize(.small)
                .disabled(!store.canUndoCurrentContest)

                Spacer()

                Button {
                    isShowingManage = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .padding(.vertical, 4) // clean hit area + stable popover anchor
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage Contest")
                .popover(isPresented: $isShowingManage, arrowEdge: .top) {
                    ManagePopover(
                        store: store,
                        onOpenResults: {
                            isShowingManage = false
                            isShowingSummaryExport = true
                        },
                        onEditEntrants: {
                            isShowingEditEntrants = true
                            isShowingManage = false
                        },
                        onDone: {
                            isShowingManage = false
                        }
                    )
                    .frame(width: 520)
                    .frame(minHeight: 520, idealHeight: 620, maxHeight: 720)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .presentationCompactAdaptation(.sheet)
                }
            }
            .padding(.horizontal)
            .padding(.top, 2)
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .frame(minHeight: 130)
    }

    // MARK: - Main Content
    private var mainContent: some View {
        Group {
            if let contestIndex = store.currentContestIndex {
                let contest = store.contests[contestIndex]
                scoringView(contest: contest)
            } else {
                ContentUnavailableView(
                    "No Contests",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Add a contest to start scoring.")
                )
                .padding()
            }
        }
    }

    private func scoringView(contest: Contest) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(contest.entrants) { entrant in
                    EntrantTile(
                        name: entrant.name,
                        score: entrant.score,
                        accent: contestAccent
                    ) {
                        store.increment(entrantID: entrant.id)
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Banner
    private var bannerOverlay: some View {
        Group {
            if let msg = store.bannerMessage {
                UndoBanner(message: msg)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Sheets
    private var editEntrantsSheet: some View {
        Group {
            let entrantsBinding = store.bindingForSelectedEntrants()
            EditEntrantsSheet(
                contestName: store.contests[store.currentContestIndex ?? 0].name,
                entrants: entrantsBinding,
                onStructuralChange: {
                    store.showBanner("Entrants updated — undo history cleared.")
                }
            )
            .presentationDetents([.large])
        }
    }
}

// MARK: - Manage Popover
// Contains contest switching + inline New/Rename flows + Results + Backup Export/Import + placeholders.
private struct ManagePopover: View {
    @ObservedObject var store: TallyStore

    let onOpenResults: () -> Void
    let onEditEntrants: () -> Void
    let onDone: () -> Void

    private enum Screen {
        case menu
        case newContest
        case rename
    }

    @State private var screen: Screen = .menu
    @State private var newContestName: String = ""
    @State private var renameName: String = ""

    // MARK: - About
    @State private var isShowingAbout = false

    // MARK: - Backup / Import-Export state
    @State private var isExportingBackup = false
    @State private var backupData = Data()
    @State private var isImportingBackup = false

    // MARK: - Destructive action confirmation
    private enum DestructiveAction: Identifiable {
        case resetCurrent
        case deleteCurrent
        case resetAll
        case deleteAll

        var id: String {
            switch self {
            case .resetCurrent: return "resetCurrent"
            case .deleteCurrent: return "deleteCurrent"
            case .resetAll: return "resetAll"
            case .deleteAll: return "deleteAll"
            }
        }

        var title: String {
            switch self {
            case .resetCurrent: return "Reset this contest?"
            case .deleteCurrent: return "Delete this contest?"
            case .resetAll: return "Reset ALL contests?"
            case .deleteAll: return "Delete ALL contests?"
            }
        }

        var message: String {
            switch self {
            case .resetCurrent:
                return "This will set all scores in the current contest back to 0. This cannot be undone."
            case .deleteCurrent:
                return "This will permanently remove the current contest and its entrants/scores. This cannot be undone."
            case .resetAll:
                return "This will set all scores in every contest back to 0. This cannot be undone."
            case .deleteAll:
                return "This will permanently remove ALL contests and their entrants/scores. This cannot be undone."
            }
        }

        var confirmButtonTitle: String {
            switch self {
            case .resetCurrent: return "Reset Contest"
            case .deleteCurrent: return "Delete Contest"
            case .resetAll: return "Reset All"
            case .deleteAll: return "Delete All"
            }
        }
    }

    @State private var pendingDestructive: DestructiveAction? = nil
    @State private var showSuccessAlert = false
    @State private var successMessage = ""

    // Helps create internal padding when keyboard appears (still imperfect in popovers)
    @StateObject private var keyboard = KeyboardObserver()

    var body: some View {
        NavigationStack {
            content
                .padding(.bottom, keyboard.height * 0.85)
                .animation(.easeOut(duration: 0.18), value: keyboard.height)
                .navigationTitle("Manage")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if screen != .menu {
                            Button("Back") { screen = .menu }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onDone() }
                    }
                }
                .alert("Done", isPresented: $showSuccessAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(successMessage)
                }
                // About screen (simple help + purpose)
                .sheet(isPresented: $isShowingAbout) {
                    AboutView()
                }
        }
        // ✅ Export backup to Files
        .fileExporter(
            isPresented: $isExportingBackup,
            document: JSONBackupDocument(data: backupData),
            contentType: .json,
            defaultFilename: ExportUtil.safeFileComponent("TwistTally_Contests_Backup") + "_" + ExportUtil.timestamp()
        ) { result in
            switch result {
            case .success:
                // NOTE: This fires after the user picks a location/name in Files.
                store.showBanner("Backup exported.")
                successMessage = "Backup exported successfully."
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showSuccessAlert = true

            case .failure(let error):
                // If the user cancels, SwiftUI often reports a failure (e.g., CocoaError.userCancelled).
                // We keep this lightweight and only show a message.
                store.showBanner("Export canceled or failed.")
                successMessage = "Export canceled or failed: \(error.localizedDescription)"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showSuccessAlert = true
            }
        }
        // ✅ Import backup from Files (REPLACES all contests)
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.json]
        ) { result in
            do {
                let url = try result.get()

                // ✅ iPad Files access: request permission to read this file URL
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { url.stopAccessingSecurityScopedResource() }
                }

                let data = try Data(contentsOf: url)

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                // Preferred: full PersistedState snapshot (includes selectedContestID)
                if let state = try? decoder.decode(PersistedState.self, from: data) {
                    store.replaceAllContests(contests: state.contests, selectedID: state.selectedContestID)
                    store.showBanner("Imported contests (replaced).")
                    screen = .menu
                    return
                }

                // Fallback: just [Contest]
                let contests = try decoder.decode([Contest].self, from: data)
                store.replaceAllContests(contests: contests, selectedID: contests.first?.id)
                store.showBanner("Imported contests (replaced).")
                screen = .menu

            } catch {
                store.showBanner("Import failed: \(error.localizedDescription)")
            }
        }
        .onAppear {
            if let idx = store.currentContestIndex {
                renameName = store.contests[idx].name
            }
            newContestName = store.defaultNewContestName()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .menu:
            menuView
        case .newContest:
            newContestView
        case .rename:
            renameView
        }
    }

    // MARK: - Menu
    private var menuView: some View {
        Form {

            // Contest selection + create/rename
            Section("Contest") {
                Picker("Current Contest", selection: $store.selectedContestID) {
                    ForEach(store.contests) { contest in
                        Text(contest.name).tag(Optional(contest.id))
                    }
                }
                .pickerStyle(.menu)

                Button {
                    newContestName = store.defaultNewContestName()
                    screen = .newContest
                } label: {
                    Label("New Contest", systemImage: "plus")
                }

                Button {
                    if let idx = store.currentContestIndex {
                        renameName = store.contests[idx].name
                    }
                    screen = .rename
                } label: {
                    Label("Rename Contest", systemImage: "square.and.pencil")
                }
                .disabled(store.currentContestIndex == nil)

                // Edit entrants belongs with the other *current contest* actions.
                Button {
                    onEditEntrants()
                } label: {
                    Label("Edit Entrants", systemImage: "person.3")
                }
                .disabled(store.currentContestIndex == nil)

                // Placeholder buttons under Rename Contest (current contest)
                Button(role: .destructive) {
                    pendingDestructive = .resetCurrent
                } label: {
                    Label("Reset Contest", systemImage: "arrow.counterclockwise")
                }
                .disabled(store.currentContestIndex == nil)

                Button(role: .destructive) {
                    pendingDestructive = .deleteCurrent
                } label: {
                    Label("Delete Contest", systemImage: "trash")
                }
                .disabled(store.currentContestIndex == nil)
            }

            // Results
            Section("Results") {
                Button {
                    onOpenResults()
                } label: {
                    Label("Results & Export", systemImage: "square.and.arrow.up")
                }

                Text("Share results as a summary PDF, or export full scores as CSV.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // About / Help
            Section("About") {
                Button {
                    isShowingAbout = true
                } label: {
                    Label("About Twist & Tally", systemImage: "info.circle")
                }

                Text("Quick tips, how it works, and why this app exists.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Backup export/import
            Section("Backup") {
                Button {
                    // Versioned snapshot (contests + selected ID)
                    let snapshot = PersistedState(
                        schemaVersion: PersistedState.currentSchemaVersion,
                        contests: store.contests,
                        selectedContestID: store.selectedContestID
                    )

                    do {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        encoder.dateEncodingStrategy = .iso8601
                        backupData = try encoder.encode(snapshot)
                        isExportingBackup = true
                    } catch {
                        store.showBanner("Could not create backup.")
                    }
                } label: {
                    Label("Export Contests (.json)", systemImage: "square.and.arrow.up")
                }

                Button {
                    isImportingBackup = true
                } label: {
                    Label("Import Contests (.json)", systemImage: "square.and.arrow.down")
                }

                Text("Export a backup you can re-import later. Import replaces the current contests.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Placeholder buttons for ALL contests
            Section("All Contests") {
                Button(role: .destructive) {
                    pendingDestructive = .resetAll
                } label: {
                    Label("Reset All Contests", systemImage: "arrow.counterclockwise")
                }
                .disabled(store.contests.isEmpty)

                Button(role: .destructive) {
                    pendingDestructive = .deleteAll
                } label: {
                    Label("Delete All Contests", systemImage: "trash.slash")
                }
                .disabled(store.contests.isEmpty)

                Text("These actions affect every contest in the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Tip: Use Manage for setup. Scoring stays fast on the main screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        // NOTE: On iPad, `.confirmationDialog` often presents from the bottom (action-sheet style),
        // even when attached to a view inside a popover.
        // Using `.alert` keeps the confirmation centered within the current presentation.
        .alert(
            pendingDestructive?.title ?? "Confirm",
            isPresented: Binding(
                get: { pendingDestructive != nil },
                set: { if !$0 { pendingDestructive = nil } }
            )
        ) {
            Button(pendingDestructive?.confirmButtonTitle ?? "Confirm", role: .destructive) {
                guard let action = pendingDestructive else { return }
                pendingDestructive = nil

                switch action {
                case .resetCurrent:
                    store.resetCurrentContest()
                    store.showBanner("Contest reset.")
                    successMessage = "Contest scores were reset to 0."
                case .deleteCurrent:
                    store.deleteCurrentContest()
                    store.showBanner("Contest deleted.")
                    successMessage = "Contest was deleted."
                case .resetAll:
                    store.resetAllContests()
                    store.showBanner("All contests reset.")
                    successMessage = "All contest scores were reset to 0."
                case .deleteAll:
                    store.deleteAllContests()
                    store.showBanner("All contests deleted.")
                    successMessage = "All contests were deleted."
                }

                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showSuccessAlert = true
            }

            Button("Cancel", role: .cancel) {
                pendingDestructive = nil
            }
        } message: {
            Text(pendingDestructive?.message ?? "")
        }
    }

    // MARK: - New Contest
    private var newContestView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Contest Name")
                    .font(.headline)

                TextField("New contest name", text: $newContestName)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)

                Button {
                    store.addContest(named: newContestName)
                    newContestName = store.defaultNewContestName()
                    screen = .menu
                } label: {
                    Text("Create Contest")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    // MARK: - Rename Contest
    private var renameView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Contest Name")
                    .font(.headline)

                TextField("Contest name", text: $renameName)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)

                Button {
                    let binding = store.bindingForCurrentContestName()
                    binding.wrappedValue = renameName
                    screen = .menu
                } label: {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

// MARK: - Small “bounce” score text for leaderboard
struct BouncyScoreText: View {
    let value: Int
    @State private var bump = false

    var body: some View {
        Text("\(value)")
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .scaleEffect(bump ? 1.18 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: bump)
            .onChange(of: value) { _, _ in
                bump = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    bump = false
                }
            }
            .accessibilityLabel("Score \(value)")
    }
}

// MARK: - Top 5 Strip (responsive + per-contest accent + flash feedback)
struct TopFiveStrip: View {
    let entrants: [Entrant]
    let accent: Color
    let onTapEntrant: (UUID) -> Void

    private var topFive: [Entrant] {
        entrants
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.name < rhs.name }
                return lhs.score > rhs.score
            }
            .prefix(5)
            .map { $0 }
    }

    @State private var flashIndex: Int? = nil
    @State private var sweep = false

    var body: some View {
        GeometryReader { geo in
            let isCompact = geo.size.width < 650
            let items = topFive

            Group {
                if isCompact {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            slotButton(at: 0, items: items)
                            slotButton(at: 1, items: items)
                            slotButton(at: 2, items: items)
                        }
                        HStack(spacing: 8) {
                            slotButton(at: 3, items: items)
                            slotButton(at: 4, items: items)
                            Color.clear.frame(width: 76, height: 44)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { index in
                            slotButton(at: index, items: items)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(accent.opacity(0.45))
                    .frame(height: 1)
                    .offset(y: 10)
                    .opacity(0.85)
            }
        }
        .frame(height: 56)
    }

    @ViewBuilder
    private func slotButton(at index: Int, items: [Entrant]) -> some View {
        let width: CGFloat = 76

        if index < items.count {
            let entrant = items[index]

            Button {
                onTapEntrant(entrant.id)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                animateFlash(for: index)
            } label: {
                ZStack {
                    VStack(spacing: 2) {
                        Text(entrant.name)
                            .font(.caption)
                            .lineLimit(1)

                        BouncyScoreText(value: entrant.score)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minWidth: width, minHeight: 44)

                    leaderboardFlash
                        .opacity(flashIndex == index ? 1 : 0)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .allowsHitTesting(false)
                }
                .background(accent.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accent.opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(TallyPressStyle())
            .accessibilityLabel("Leaderboard: \(entrant.name), score \(entrant.score)")
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color("TileBackground"))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
                .frame(minWidth: width, minHeight: 44)
                .opacity(0.55)
                .accessibilityHidden(true)
        }
    }

    private var leaderboardFlash: some View {
        LinearGradient(
            colors: [
                accent.opacity(0.0),
                accent.opacity(0.30),
                Color.white.opacity(0.14),
                accent.opacity(0.22),
                accent.opacity(0.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .rotationEffect(.degrees(10))
        .offset(x: sweep ? 36 : -36)
        .blendMode(.plusLighter)
        .animation(.easeOut(duration: 0.18), value: sweep)
    }

    private func animateFlash(for index: Int) {
        flashIndex = index
        sweep = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            sweep = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            flashIndex = nil
            sweep = false
        }
    }
}

// MARK: - Tap feedback style
struct TallyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Entrant Tile (flash + watermark pulse)
struct EntrantTile: View {
    let name: String
    let score: Int
    let accent: Color
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var flash = false
    @State private var sweep = false
    @State private var pulse = false

    var body: some View {
        Button {
            onTap()
            animateFlash()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack(alignment: .topTrailing) {

                RoundedRectangle(cornerRadius: 16)
                    .fill(Color("TileBackground"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(accent.opacity(0.28), lineWidth: 1)
                    )
                    .overlay(alignment: .center) {
                        Image(systemName: "plus")
                            .font(.system(size: 72, weight: .bold))
                            .foregroundStyle(accent)
                            .opacity(colorScheme == .dark ? 0.09 : 0.05)
                            .rotationEffect(.degrees(-8))
                            .scaleEffect(pulse ? 1.08 : 1.0)
                            .animation(.easeOut(duration: 0.18), value: pulse)
                            .accessibilityHidden(true)
                    }
                    .overlay(
                        gradientFlash.mask(RoundedRectangle(cornerRadius: 16))
                    )

                Text("\(score)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.88))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                    .padding(8)

                VStack(spacing: 6) {
                    Spacer(minLength: 6)
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                }
                .padding(.top, 28)
                .padding(.bottom, 8)
            }
            .frame(height: 105)
        }
        .buttonStyle(TallyPressStyle())
        .accessibilityLabel("\(name), score \(score)")
    }

    private var gradientFlash: some View {
        LinearGradient(
            colors: [
                accent.opacity(0.0),
                accent.opacity(flash ? 0.38 : 0.0),
                Color.white.opacity(flash ? 0.18 : 0.0),
                accent.opacity(flash ? 0.30 : 0.0),
                accent.opacity(0.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .rotationEffect(.degrees(18))
        .offset(x: sweep ? 80 : -80)
        .animation(.easeOut(duration: 0.22), value: sweep)
        .animation(.easeOut(duration: 0.12), value: flash)
        .blendMode(.plusLighter)
    }

    private func animateFlash() {
        flash = true
        sweep = false
        pulse = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            sweep = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            pulse = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            flash = false
        }
    }
}

// MARK: - Banner
struct UndoBanner: View {
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

// MARK: - Edit Entrants Sheet
struct EditEntrantsSheet: View {
    let contestName: String
    @Binding var entrants: [Entrant]
    let onStructuralChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newEntrantName: String = ""

    var body: some View {
        NavigationStack {
            List {
                // Instructions (shown under the title; not inside an input-looking box)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tip: Swipe left to delete. Tap Edit to rename or reorder (drag the handles).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)

                Section("Add Entrant") {
                    HStack {
                        TextField("Name", text: $newEntrantName)

                        Button("Add") {
                            let trimmed = newEntrantName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            entrants.append(Entrant(name: trimmed))
                            newEntrantName = ""
                            onStructuralChange()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("BrandAccent"))
                        .controlSize(.small)
                    }
                }

                Section {
                    ForEach($entrants) { $entrant in
                        HStack {
                            TextField("Entrant name", text: $entrant.name)
                            Spacer()
                            Text("\(entrant.score)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    // ✅ Allow drag-reordering when the user taps the Edit button.
                    // This is considered a structural change, so we clear undo history.
                    .onMove { fromOffsets, toOffset in
                        entrants.move(fromOffsets: fromOffsets, toOffset: toOffset)
                        onStructuralChange()
                    }
                    .onDelete { indexSet in
                        entrants.remove(atOffsets: indexSet)
                        onStructuralChange()
                    }
                } header: {
                    Text("Entrants")
                }
            }
            .navigationTitle("Edit Entrants")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(contestName).font(.headline)
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Keyboard Observer
final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()

    init() {
        let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect }
            .map { $0.height }

        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }

        Publishers.Merge(willShow, willHide)
            .receive(on: RunLoop.main)
            .sink { [weak self] h in
                self?.height = h
            }
            .store(in: &cancellables)
    }
}

// MARK: - Hex Color Helper
private extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }

        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - JSON Backup Document (for .fileExporter)
private struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Results & Export View
// Presented as a sheet from the Manage popover.
// Shares:
// 1) Results PDF (organizer-friendly)
// 2) All scores CSV (grouped by contest; entrants sorted by score desc)

struct ResultsExportView: View {
    @ObservedObject var store: TallyStore

    @Environment(\.dismiss) private var dismiss

    // Share sheet payload (using `.sheet(item:)` ensures the sheet is created
    // only after the payload exists, avoiding the “blank share sheet first time” issue).
    private struct SharePayload: Identifiable {
        let id = UUID()
        let items: [Any]
        let kind: Kind

        enum Kind {
            case pdf
            case csv
        }
    }

    @State private var sharePayload: SharePayload? = nil

    // Post-share feedback
    @State private var showResultAlert = false
    @State private var resultMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    // Action buttons (top)
                    VStack(spacing: 10) {
                        Button {
                            shareResultsPDF()
                        } label: {
                            Label("Share Results as PDF", systemImage: "doc.richtext")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            shareAllScoresCSV()
                        } label: {
                            Label("Share All Scores as CSV", systemImage: "tablecells")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)

                    Divider().padding(.horizontal)

                    // Title
                    Text("Contest Results")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)

                    // Per-contest leaderboards
                    VStack(spacing: 14) {
                        ForEach(store.contests) { contest in
                            ResultsContestCard(contest: contest)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $sharePayload) { payload in
            ActivityViewController(items: payload.items) { completed, _ in
                // Fires when the share sheet is dismissed.
                resultMessage = completed ? "Shared successfully." : "Share canceled."
                showResultAlert = true

                // Clear payload so the next share always creates a fresh controller.
                sharePayload = nil
            }
        }
        .alert("Results", isPresented: $showResultAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage)
        }
    }

    // MARK: - Share actions

    private func shareResultsPDF() {
        // Build the SwiftUI content we want rendered into the PDF.
        let pdfView = ResultsPDFView(contests: store.contests)

        // Render to a temp PDF URL.
        guard let url = PDFExporter.makePDF(
            title: "TwistTally_Results_\(ExportUtil.timestamp())",
            view: pdfView,
            pageWidth: 1024
        ) else {
            resultMessage = "Could not generate PDF."
            showResultAlert = true
            return
        }

        presentShare(items: [url], kind: .pdf)
    }

    private func shareAllScoresCSV() {
        // CSV grouped by contest; each contest sorted by score desc (tie: name).
        let csv = CSVExporter.makeGroupedScoresCSV(contests: store.contests)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(ExportUtil.csvFileName(prefix: "TwistTally_AllScores"))

        do {
            try csv.data(using: .utf8)?.write(to: fileURL, options: .atomic)
            presentShare(items: [fileURL], kind: .csv)
        } catch {
            resultMessage = "Could not write CSV file."
            showResultAlert = true
        }
    }

    private func presentShare(items: [Any], kind: SharePayload.Kind) {
        // Ensure any alert isn’t competing with the share sheet.
        showResultAlert = false

        // Create a fresh payload so SwiftUI builds a brand-new UIActivityViewController.
        // Presenting on the next run loop helps iPadOS avoid a “blank first sheet” glitch.
        DispatchQueue.main.async {
            sharePayload = SharePayload(items: items, kind: kind)
        }
    }
}

// MARK: - Results PDF content

private struct ResultsPDFView: View {
    let contests: [Contest]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Twist & Tally — Results")
                .font(.title)
                .fontWeight(.bold)

            Divider()

            ForEach(contests) { contest in
                ResultsContestCard(contest: contest)
            }

            Spacer(minLength: 24)

            // Footer (centered)
            HStack {
                Spacer()
                Text("Tallied on \(ExportUtil.timestamp())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 12)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Contest card used by both on-screen Results and the PDF

private struct ResultsContestCard: View {
    let contest: Contest

    // Sort entrants by score desc, tie-break by name.
    private var sortedEntrants: [Entrant] {
        contest.entrants.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.name < $1.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(contest.name)
                .font(.headline)

            // Leaderboard list (top 10)
            ForEach(Array(sortedEntrants.prefix(10).enumerated()), id: \.element.id) { i, e in
                HStack {
                    Text("#\(i + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)

                    Text(e.name)
                        .lineLimit(1)

                    Spacer()

                    Text("\(e.score)")
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }

            if contest.entrants.count > 10 {
                Text("(+\(contest.entrants.count - 10) more)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - UIKit share sheet wrapper

private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]
    let completion: (_ completed: Bool, _ activityType: UIActivity.ActivityType?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { activityType, completed, _, _ in
            completion(completed, activityType)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}




// MARK: - About View
// A lightweight, organizer-friendly explanation of what the app does.

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    Text("Twist & Tally")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("A fast, simple tally counter for balloon jams, contests, and live judging.")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Divider()

                    Group {
                        Text("How to use")
                            .font(.title3)
                            .fontWeight(.semibold)

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Tap an entrant tile to add +1.", systemImage: "hand.tap")
                            Label("Use Undo to revert the last few taps (per contest).", systemImage: "arrow.uturn.backward")
                            Label("Use Manage to add/rename contests and edit entrants.", systemImage: "ellipsis.circle")
                            Label("Use Results & Export to share a PDF leaderboard or a CSV of scores.", systemImage: "square.and.arrow.up")
                        }
                        .font(.body)
                    }

                    Group {
                        Text("Results")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text("The Results screen is what you send to organizers. It shows each contest’s leaderboard and exports:")

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Results PDF: clean leaderboards for printing or sharing.", systemImage: "doc.richtext")
                            Label("All Scores CSV: every entrant, grouped by contest, sorted by score.", systemImage: "tablecells")
                        }
                        .font(.body)
                    }

                    Group {
                        Text("Backup")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text("You can export your contests to a .json backup file and import it later. Import replaces the current contests.")
                            .font(.body)
                    }

                    Group {
                        Text("Why it was made")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text("This app was built to keep scoring fast and reliable during live events—no spreadsheets, no accidental edits, and no hunting for the right screen when the room is loud.")
                            .font(.body)
                    }

                    Group {
                        Text("About the developer")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text("Twist & Tally was created by Todd Neufeld, a professional balloon artist, educator, and event producer. The app grew out of real-world judging and balloon jam scenarios where fast, distraction-free scoring mattered more than complex tools.")
                            .font(.body)
                    }

                    Spacer(minLength: 24)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
