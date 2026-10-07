import SwiftUI
import UIKit

/// Player "Sheet" mode: the scan photo with a box on every recognized note (`ScanLayout`).
/// Notes sounding now (`activeIDs`, from `SF2MIDIPlayer.activeNoteIDs`) are filled coral.
/// The photo stays at fit-to-page by default; Follow/playback never zooms or pans — only
/// highlights move. Manual +/- zoom remains for user control. Tapping near a note calls
/// `onTap` (seek there).
struct SheetFollowView: View {
    let image: UIImage
    let layout: ScanLayout
    let activeIDs: Set<Int>
    /// Kept for call-site compatibility; Follow no longer drives camera transform.
    var follow: Bool = true
    /// Notes drawn with a secondary tint (e.g. inside an A–B loop).
    var tinted: Set<Int> = []
    /// Badges by note id (e.g. "A" / "B" loop marks).
    var badges: [Int: String] = [:]
    let onTap: (RecognizedNote) -> Void

    /// 1 = entire page visible (aspect-fit); higher values magnify around that baseline.
    @State private var zoom: CGFloat = 1
    static let zoomRange: ClosedRange<CGFloat> = 1 ... 4

    var body: some View {
        GeometryReader { geo in
            let fit = Self.fitScale(imageSize: layout.imageSize, viewport: geo.size)
            let scale = fit * zoom
            let width = CGFloat(layout.imageWidth) * scale
            let height = CGFloat(layout.imageHeight) * scale
            // Center the sheet when it is smaller than the viewport (fit-to-page); allow
            // pan only when the user has zoomed in past the viewport.
            let contentW = max(width, geo.size.width)
            let contentH = max(height, geo.size.height)
            let originX = (contentW - width) / 2
            let originY = (contentH - height) / 2
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    Color.clear.frame(width: contentW, height: contentH)
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: width, height: height)
                        .offset(x: originX, y: originY)
                        .accessibilityHidden(true)
                    ForEach(layout.boxedNotes) { n in
                        noteBox(n, scale: scale, originX: originX, originY: originY)
                    }
                }
                .frame(width: contentW, height: contentH, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in
                    let p = CGPoint(x: (v.location.x - originX) / scale, y: (v.location.y - originY) / scale)
                    if let n = layout.note(near: p, maxDistance: Double(36 / max(scale, 0.001))) { onTap(n) }
                })
            }
            // Follow/playback intentionally do not scroll or zoom — keep fit-to-page transform.
            // `follow` is retained for API compatibility but does not change the camera.
            .accessibilityValue(follow ? "Follow on" : "Follow off")
        }
        .overlay(alignment: .bottomTrailing) { zoomControls }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sheet music, \(layout.boxedNotes.count) notes. Tap a note to play from there.")
        .accessibilityIdentifier("player.sheet")
    }

    /// Scale that fits the full sheet inside `viewport` (no crop).
    static func fitScale(imageSize: CGSize, viewport: CGSize) -> CGFloat {
        let iw = max(1, imageSize.width)
        let ih = max(1, imageSize.height)
        let vw = max(1, viewport.width)
        let vh = max(1, viewport.height)
        return min(vw / iw, vh / ih)
    }

    @ViewBuilder
    private func noteBox(_ n: RecognizedNote, scale: CGFloat, originX: CGFloat, originY: CGFloat) -> some View {
        if let r = n.rect {
            let active = activeIDs.contains(n.noteIndex)
            let w = max(r.width * scale, 10), h = max(r.height * scale, 10)
            let x = originX + r.midX * scale - w / 2
            let y = originY + r.midY * scale - h / 2
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
                .offset(x: x, y: y)
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
