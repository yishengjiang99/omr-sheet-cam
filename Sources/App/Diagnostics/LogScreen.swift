import SwiftUI

/// Event log: newest first, level + category filters, Clear, Copy as prompt.
struct LogScreen: View {
    @ObservedObject private var log = DiagnosticsLog.shared
    @State private var level: DiagnosticsEvent.Level?
    @State private var category: DiagnosticsEvent.Category?
    @State private var expanded: Set<UUID> = []
    @State private var confirmClear = false
    @State private var toast: String?

    private var filtered: [DiagnosticsEvent] {
        log.events.reversed().filter {
            (level == nil || $0.level == level) && (category == nil || $0.category == category)
        }
    }

    var body: some View {
        List {
            Section {
                Text(DeviceInfo.current.headerLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Picker("Level", selection: $level) {
                    Text("All levels").tag(DiagnosticsEvent.Level?.none)
                    ForEach(DiagnosticsEvent.Level.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                Picker("Category", selection: $category) {
                    Text("All categories").tag(DiagnosticsEvent.Category?.none)
                    ForEach(DiagnosticsEvent.Category.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
            }
            Section("\(filtered.count) of \(log.events.count) events") {
                if filtered.isEmpty {
                    Text("No events").foregroundStyle(.secondary)
                }
                ForEach(filtered) { e in
                    row(e)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if expanded.contains(e.id) { expanded.remove(e.id) } else { expanded.insert(e.id) }
                        }
                }
            }
        }
        .navigationTitle("Event log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                CopyPromptButton(toast: $toast)
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Clear", role: .destructive) { confirmClear = true }
                    .disabled(log.events.isEmpty)
            }
        }
        .confirmationDialog("Clear all events?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { log.clear() }
        }
        .toast($toast)
    }

    private func row(_ e: DiagnosticsEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon(e.level)).foregroundStyle(color(e.level))
                Text(e.category.rawValue).font(.caption.weight(.semibold))
                Spacer()
                Text(e.date, format: .dateTime.hour().minute().second())
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            Text(e.message)
                .font(.footnote.monospaced())
                .lineLimit(expanded.contains(e.id) ? nil : 3)
            if expanded.contains(e.id), let p = e.payload, !p.isEmpty {
                ForEach(p.keys.sorted(), id: \.self) { k in
                    Text("\(k): \(p[k] ?? "")")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func icon(_ l: DiagnosticsEvent.Level) -> String {
        switch l {
        case .info: return "info.circle"
        case .warn: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    private func color(_ l: DiagnosticsEvent.Level) -> Color {
        switch l {
        case .info: return .secondary
        case .warn: return .orange
        case .error: return .red
        }
    }
}
