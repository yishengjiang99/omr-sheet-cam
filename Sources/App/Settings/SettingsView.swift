import StoreKit
import SwiftUI

/// Settings sheet (redesign 06a/06b): Playback (instrument, tempo), About (version, rate, privacy,
/// source code & license). Tapping Version 5 times reveals the Developer section (event log,
/// copy diagnostics as prompt, model self-test, compare test staff), persisted in UserDefaults.
struct SettingsView: View {
    enum Section: String, CaseIterable { case playback, about, developer }
    enum AboutRow: String, CaseIterable { case version, rate, privacy, sourceCode }
    enum DeveloperRow: String, CaseIterable {
        case eventLog, copyPrompt, selfTest, segnetSelfTest, compareStaff, turnOff
    }

    static let repoURL = URL(string: "https://github.com/yishengjiang99/omr-sheet-cam")!

    /// Sections the sheet shows (Developer only once unlocked). The view renders exactly these.
    static func sections(developerEnabled: Bool) -> [Section] {
        developerEnabled ? Section.allCases : [.playback, .about]
    }

    static let aboutRows = AboutRow.allCases
    static let developerRows = DeveloperRow.allCases

    static func title(_ row: AboutRow) -> String {
        switch row {
        case .version: return "Version"
        case .rate: return "Rate AI Camera – Music Reader"
        case .privacy: return "Privacy"
        case .sourceCode: return "Source code & license"
        }
    }

    static func title(_ row: DeveloperRow) -> String {
        switch row {
        case .eventLog: return "Event log"
        case .copyPrompt: return "Copy diagnostics as prompt"
        case .selfTest: return "Run model self-test"
        case .segnetSelfTest: return "SegNet self-test"
        case .compareStaff: return "Compare test staff"
        case .turnOff: return "Turn off developer mode"
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var developer = DeveloperMode.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(Self.sections(developerEnabled: developer.isEnabled), id: \.self) { section in
                    switch section {
                    case .playback: playback
                    case .about: about
                    case .developer: developerSection
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
            .toast($toast)
        }
        .tint(Theme.coral)
    }

    private var playback: some View {
        SwiftUI.Section("Playback") {
            Picker(selection: $settings.instrument) {
                ForEach(Instrument.all) { Text($0.name).tag($0) }
            } label: {
                SettingsLabel("Instrument", icon: "pianokeys", color: .orange)
            }
            .pickerStyle(.navigationLink)
            Picker(selection: $settings.tempo) {
                ForEach(AppSettings.tempoChoices, id: \.self) { Text(AppSettings.tempoLabel($0)).tag($0) }
            } label: {
                SettingsLabel("Tempo", icon: "metronome", color: Theme.coral)
            }
            .pickerStyle(.navigationLink)
        }
    }

    private var about: some View {
        SwiftUI.Section {
            ForEach(Self.aboutRows, id: \.self) { row in
                switch row {
                case .version:
                    Button {
                        let before = developer.tapsRemaining
                        if developer.registerVersionTap() {
                            toast = "Developer mode on"
                        } else if !developer.isEnabled, before <= 3 {
                            toast = "\(developer.tapsRemaining) more tap\(developer.tapsRemaining == 1 ? "" : "s") for developer mode"
                        }
                    } label: {
                        HStack {
                            SettingsLabel(Self.title(row), icon: "info", color: .gray)
                            Spacer()
                            Text(Self.versionString).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.version")
                case .rate:
                    Button { requestReview() } label: {
                        SettingsLabel(Self.title(row), icon: "star.fill", color: .yellow)
                    }
                    .buttonStyle(.plain)
                case .privacy:
                    NavigationLink { PrivacyScreen() } label: {
                        SettingsLabel(Self.title(row), icon: "hand.raised.fill", color: .blue)
                    }
                case .sourceCode:
                    NavigationLink { SourceCodeScreen() } label: {
                        SettingsLabel(Self.title(row), icon: "chevron.left.forwardslash.chevron.right", color: .indigo)
                    }
                    .accessibilityIdentifier("settings.sourceCode")
                }
            }
        } header: {
            Text("About")
        } footer: {
            Text("Your music is read right on your iPhone. Photos never leave your device.")
        }
    }

    private var developerSection: some View {
        SwiftUI.Section {
            ForEach(Self.developerRows, id: \.self) { row in
                switch row {
                case .eventLog:
                    NavigationLink { LogScreen() } label: { SettingsLabel(Self.title(row), icon: "list.bullet.rectangle", color: .purple) }
                case .copyPrompt:
                    CopyPromptButton(toast: $toast, title: Self.title(row))
                case .selfTest:
                    NavigationLink { Gate1RootView(embedded: true) } label: { SettingsLabel(Self.title(row), icon: "checkmark", color: .purple) }
                case .segnetSelfTest:
                    NavigationLink { SegNetSelfTestScreen() } label: { SettingsLabel(Self.title(row), icon: "square.grid.3x3", color: .purple) }
                        .accessibilityIdentifier("settings.segnetSelfTest")
                case .compareStaff:
                    NavigationLink { Gate1CompareScreen() } label: { SettingsLabel(Self.title(row), icon: "rectangle.on.rectangle", color: .purple) }
                case .turnOff:
                    Button(Self.title(row), role: .destructive) { developer.setEnabled(false) }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Text("Developer")
                Text("On").font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.coral, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .accessibilityIdentifier("settings.developer")
    }
}

/// Icon tile + title, Settings-style.
struct SettingsLabel: View {
    let title: String
    let icon: String
    let color: Color

    init(_ title: String, icon: String, color: Color) {
        self.title = title; self.icon = icon; self.color = color
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title).foregroundStyle(.primary)
        }
    }
}

struct PrivacyScreen: View {
    var body: some View {
        List {
            Text("AI Camera – Music Reader reads your sheet music right on your iPhone. Photos and recognized music are stored only on this device and are never uploaded.")
            Text("There is no account, no sign-in, no analytics and no network access. The diagnostics event log stays on the device unless you copy it yourself.")
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings → About → Source code & license: repo link, AGPL-3.0 license, NOTICE, acknowledgements.
struct SourceCodeScreen: View {
    var body: some View {
        List {
            Section {
                Link(destination: SettingsView.repoURL) {
                    Label("github.com/yishengjiang99/omr-sheet-cam", systemImage: "arrow.up.right.square")
                }
                .accessibilityIdentifier("settings.repoLink")
            } footer: {
                Text("This app is free software under the GNU Affero General Public License v3.0. The complete source code is available at the link above.")
            }
            Section {
                NavigationLink("License (AGPL-3.0)") { LicenseTextScreen(title: "License", text: LicenseTexts.license()) }
                    .accessibilityIdentifier("settings.license")
                NavigationLink("Notice") { LicenseTextScreen(title: "Notice", text: LicenseTexts.notice()) }
                NavigationLink("Acknowledgements") { AcknowledgementsView() }
            }
        }
        .navigationTitle("Source code & license")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LicenseTextScreen: View {
    let title: String
    let text: String

    /// Paragraph chunks so very long texts (ORT notices, ~320 KB) render lazily.
    private var chunks: [String] {
        var out: [String] = [], cur = ""
        for para in text.components(separatedBy: "\n\n") {
            if cur.count + para.count > 4000, !cur.isEmpty { out.append(cur); cur = "" }
            cur += (cur.isEmpty ? "" : "\n\n") + para
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                    Text(chunk)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Repo-root LICENSE (AGPL-3.0) and NOTICE, and `Licenses/*.txt`, bundled as app resources.
enum LicenseTexts {
    static func license(bundle: Bundle = .main) -> String { load("LICENSE", ext: nil, bundle: bundle) }
    static func notice(bundle: Bundle = .main) -> String { load("NOTICE", ext: nil, bundle: bundle) }
    static func resource(_ name: String, bundle: Bundle = .main) -> String { load(name, ext: "txt", bundle: bundle) }

    static func isBundled(_ name: String, ext: String? = nil, bundle: Bundle = .main) -> Bool {
        bundle.url(forResource: name, withExtension: ext) != nil
    }

    private static func load(_ name: String, ext: String?, bundle: Bundle) -> String {
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let s = try? String(contentsOf: url, encoding: .utf8), !s.isEmpty
        else { return "\(name) not bundled. See \(SettingsView.repoURL.absoluteString)" }
        return s
    }
}
