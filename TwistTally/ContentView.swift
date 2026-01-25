//
//  ContentView.swift
//  TwistTally
//
//  Created by Todd Neufeld on 1/24/26.
//

import SwiftUI
import UIKit
import Combine

struct ContentView: View {

    // MARK: - Store

    @StateObject private var store = TallyStore()

    // MARK: - UI State

    @State private var isShowingEditEntrants = false
    @State private var isShowingManage = false

    // Summary & Export sheet
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

    private var contestAccentSoft: Color {
        contestAccent.opacity(0.18)
    }

    private var currentEntrants: [Entrant] {
        guard let idx = store.currentContestIndex else { return [] }
        return store.contests[idx].entrants
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            mainLayout
                // Top-left inline logo + app title
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

                // Summary & Export sheet
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
            .padding(.top, 38)   //  reserves space for Undo/Manage row

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

                // RIGHT: Manage
                Button {
                    isShowingManage = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .padding(.vertical, 4)   // gives a clean hit area + stable popover anchor
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage Contest")
                .popover(isPresented: $isShowingManage, arrowEdge: .top) {
                    ManagePopover(
                        store: store,
                        onOpenSummary: {
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
            .padding(.top, 2)   // optional: pins controls a tad lower from the top edge
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .frame(minHeight: 130) // optional bump; can keep 110 if you want
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
                    // Entrant tile gets per-contest accent + animated gradient flash
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
// Contains contest switching + inline New/Rename flows + Summary & Export + Edit Entrants.

private struct ManagePopover: View {
    @ObservedObject var store: TallyStore

    // Summary & Export entrypoint
    let onOpenSummary: () -> Void

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
            }

            Section("Results") {
                Button {
                    onOpenSummary()
                } label: {
                    Label("Results & Export", systemImage: "square.and.arrow.up")
                }

                Text("Share results as a summary PDF, or export full scores as CSV.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if store.currentContestIndex != nil {
                Section("Edit") {
                    Button {
                        onEditEntrants()
                    } label: {
                        Label("Edit Entrants", systemImage: "person.3")
                    }
                }
            }

            Section {
                Text("Tip: Use Manage for setup. Scoring stays fast on the main screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - New Contest (ScrollView so it can move internally)

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

    // MARK: - Rename (ScrollView so it can move internally)

    private var renameView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Contest Name")
                    .font(.headline)

                TextField("Contest name", text: $renameName)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)

                Button {
                    // Use store’s binding (compiler-safe) to commit rename
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


/// A tiny “bounce” animation that triggers whenever `value` changes.
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
                // Trigger a quick “up then back” bounce.
                bump = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    bump = false
                }
            }
            .accessibilityLabel("Score \(value)")
    }
}

// MARK: - Top 5 Strip (responsive + per-contest accent)
//  In landscape: 5 across
//  In portrait/compact: 3 + 2 layout
//  Accent color changes with contest selection
//  NEW: leaderboard buttons flash + sweep feedback on tap

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

    // NEW: feedback state for a quick flash on the tapped leaderboard slot
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
                // Action
                onTapEntrant(entrant.id)

                // Haptic feedback (same feel as tile taps)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                // Visual feedback: flash the button that was tapped
                animateFlash(for: index)
            } label: {
                ZStack {
                    // Base content
                    VStack(spacing: 2) {
                        Text(entrant.name)
                            .font(.caption)
                            .lineLimit(1)

                        BouncyScoreText(value: entrant.score)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minWidth: width, minHeight: 44)

                    // NEW: quick sweep overlay
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

    // MARK: - Flash overlay (same “language” as entrant tile)

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
        .rotationEffect(.degrees(10))               // slightly less rotation than tiles
        .offset(x: sweep ? 36 : -36)                // smaller sweep distance than tiles
        .blendMode(.plusLighter)
        .animation(.easeOut(duration: 0.18), value: sweep)
    }

    private func animateFlash(for index: Int) {
        flashIndex = index
        sweep = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            sweep = true
        }

        // clear quickly
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

// MARK: - Entrant Tile
// ✅ Per-contest accent
// ✅ Animated “gradient sweep” flash on +1
// ✅ Watermark "+" with subtle pulse
// ✅ Score badge uses accent
// ✅ VoiceOver label includes name + score

struct EntrantTile: View {
    let name: String
    let score: Int
    let accent: Color
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var flash = false
    @State private var sweep = false

    // NEW: watermark pulse
    @State private var pulse = false

    var body: some View {
        Button {
            onTap()
            animateFlash()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack(alignment: .topTrailing) {

                // Base tile
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color("TileBackground"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(accent.opacity(0.28), lineWidth: 1)
                    )

                    // ✅ Centered watermark "+" (decorative)
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

                    // ✅ Gradient sweep flash overlay on tap
                    .overlay(
                        gradientFlash.mask(RoundedRectangle(cornerRadius: 16))
                    )

                // Score badge
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

                // Entrant name (no repeated hint text needed now)
                VStack(spacing: 6) {
                    Spacer(minLength: 6)

                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                }
                // Reserve space beneath the score badge
                .padding(.top, 28)
                .padding(.bottom, 8)
            }
            .frame(height: 105)
        }
        .buttonStyle(TallyPressStyle())
        .accessibilityLabel("\(name), score \(score)")
    }

    private var gradientFlash: some View {
        // Diagonal sweep that animates across the tile on tap
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
        // Flash + sweep
        flash = true
        sweep = false

        // Watermark pulse
        pulse = true

        // Kick the sweep very slightly after tap
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            sweep = true
        }

        // Reset pulse quickly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            pulse = false
        }

        // Fade out flash
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
                Section {
                    Text("Delete: swipe left on a row, or tap Edit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

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

                Section("Entrants") {
                    ForEach($entrants) { $entrant in
                        HStack {
                            TextField("Entrant name", text: $entrant.name)
                            Spacer()
                            Text("\(entrant.score)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        entrants.remove(atOffsets: indexSet)
                        onStructuralChange()
                    }
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
// Used to pad internal content when the keyboard appears.
// (Popover + keyboard on iPad landscape can still be quirky; this helps but isn’t perfect.)

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
// Allows Color(hex: "#RRGGBB") for the per-contest accent.

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


// MARK: - Results & Export View
// This is presented as a sheet from the Manage popover.
// It shows a per-contest leaderboard, and provides Share actions for:
// 1) Results PDF (organizer-friendly)
// 2) Full CSV (all entrants, grouped by contest)

struct ResultsExportView: View {
    @ObservedObject var store: TallyStore

    @Environment(\.dismiss) private var dismiss

    // Share sheet state
    @State private var isShowingShare = false
    @State private var shareItems: [Any] = []

    // Simple post-share feedback
    @State private var showResultAlert = false
    @State private var resultMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    // Action buttons (top of sheet)
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
        .sheet(isPresented: $isShowingShare) {
            ActivityViewController(items: shareItems) { completed, _ in
                // This callback fires when the share sheet is dismissed.
                // We only show success if the user completed an action.
                if completed {
                    resultMessage = "Shared successfully."
                } else {
                    resultMessage = "Share canceled."
                }
                showResultAlert = true
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
        // Build a SwiftUI view for the PDF content
        let pdfView = ResultsPDFView(contests: store.contests)

        // Render to PDF URL
        guard let url = PDFExporter.makePDF(
            title: "TwistTally_Results_\(ExportUtil.timestamp())",
            view: pdfView,
            pageWidth: 1024
        ) else {
            resultMessage = "Could not generate PDF."
            showResultAlert = true
            return
        }

        presentShare(items: [url])
    }

    private func shareAllScoresCSV() {
        // CSV is grouped by contest (each contest section sorted by score desc).
        // This avoids mixing contests together in one big ranking.
        let csv = CSVExporter.makeGroupedScoresCSV(contests: store.contests)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TwistTally_AllScores_\(ExportUtil.timestamp()).csv")

        do {
            try csv.data(using: .utf8)?.write(to: fileURL, options: .atomic)
            presentShare(items: [fileURL])
        } catch {
            resultMessage = "Could not write CSV file."
            showResultAlert = true
        }
    }

    private func presentShare(items: [Any]) {
        // Avoid the “blank share sheet the first time” issue by setting items
        // and presenting on the next run loop.
        shareItems = items
        DispatchQueue.main.async {
            isShowingShare = true
        }
    }
}

// MARK: - Results PDF content
// This is the SwiftUI view we render into a PDF.

private struct ResultsPDFView: View {
    let contests: [Contest]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Twist & Tally — Results")
                .font(.title)
                .fontWeight(.bold)

            Text("Tallied on \(ExportUtil.timestamp())")
                .font(.subheadline)
                .foregroundStyle(.secondary)

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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Contest card used by both on-screen Results and the PDF

private struct ResultsContestCard: View {
    let contest: Contest

    // Sort entrants by score desc, tie-break by name
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

            // Leaderboard list (show top 10; if you want all, remove prefix)
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
