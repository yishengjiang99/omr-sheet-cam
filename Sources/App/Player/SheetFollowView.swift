import SwiftUI
import UIKit

/// Player "Sheet" mode: the scan photo with a box on every recognized note (`ScanLayout`).
/// Notes sounding now (`activeIDs`, from `SF2MIDIPlayer.activeNoteIDs`) are filled coral and,
/// while `follow` is on, scrolled to the middle. Tapping near a note calls `onTap` (seek there).
struct SheetFollowView: View {
    let image: UIImage
    let layout: ScanLayout
    let activeIDs: Set<Int>
    var follow: Bool = true
    /// Notes drawn with a secondary tint (e.g. inside an A–B loop).
    var tinted: Set<Int> = []
    /// Badges by note id (e.g. "A" / "B" loop marks).
    var badges: [Int: String] = [:]
    let onTap: (RecognizedNote) -> Void

    @State private var zoom: CGFloat = 1.6
    static let zoomRange: ClosedRange<CGFloat> = 1 ... 4

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width * zoom)
            let scale = width / CGFloat(max(1, layout.imageWidth))
            let height = CGFloat(layout.imageHeight) * scale
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: width, height: height)
                            .accessibilityHidden(true)
                        ForEach(layout.boxedNotes) { n in
                            noteBox(n, scale: scale)
                        }
                    }
                    .frame(width: width, height: height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { v in
                        let p = CGPoint(x: v.location.x / scale, y: v.location.y / scale)
                        if let n = layout.note(near: p, maxDistance: Double(36 / scale)) { onTap(n) }
                    })
                }
                .onChange(of: scrollTargetID) { _, id in
                    guard follow, let id else { return }
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                }
                .onAppear {
                    if let id = scrollTargetID ?? layout.boxedNotes.first?.noteIndex { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) { zoomControls }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sheet music, \(layout.boxedNotes.count) notes. Tap a note to play from there.")
        .accessibilityIdentifier("player.sheet")
    }

    /// First sounding note with a box; changes only when the passage moves on.
    private var scrollTargetID: Int? { layout.scrollTarget(for: activeIDs)?.noteIndex }

    @ViewBuilder
    private func noteBox(_ n: RecognizedNote, scale: CGFloat) -> some View {
        if let r = n.rect {
            let active = activeIDs.contains(n.noteIndex)
            let w = max(r.width * scale, 10), h = max(r.height * scale, 10)
            let x = r.midX * scale - w / 2, y = r.midY * scale - h / 2
            RoundedRectangle(cornerRadius: 3)
                .fill(active ? Theme.coral.opacity(0.45) : (tinted.contains(n.noteIndex) ? Color.blue.opacity(0.18) : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(active ? Theme.coral : Theme.coral.opacity(0.3), lineWidth: active ? 2 : 1)
                )
                .overlay(alignment: .top) {
                    if let b = badges[n.noteIndex] {
                        Text(b).font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 4).background(Color.blue, in: Capsule())
                            .offset(y: -16)
                    }
                }
                .frame(width: w, height: h)
                .alignmentGuide(.leading) { _ in -x }
                .alignmentGuide(.top) { _ in -y }
                .id(n.noteIndex)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 0) {
            Button { zoom = max(Self.zoomRange.lowerBound, zoom / 1.25) } label: {
                Image(systemName: "minus.magnifyingglass").frame(width: 40, height: 36)
            }
            .accessibilityLabel("Zoom out")
            .accessibilityIdentifier("player.sheet.zoomOut")
            Button { zoom = min(Self.zoomRange.upperBound, zoom * 1.25) } label: {
                Image(systemName: "plus.magnifyingglass").frame(width: 40, height: 36)
            }
            .accessibilityLabel("Zoom in")
            .accessibilityIdentifier("player.sheet.zoomIn")
        }
        .foregroundStyle(Color.primary)
        .background(.thinMaterial, in: Capsule())
        .padding(10)
    }
}
