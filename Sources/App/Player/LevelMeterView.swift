import SF2Player
import SwiftUI

/// Live output level (redesign 04-player): a scrolling row of coral bars, one per ~33 ms frame,
/// height = RMS level (dBFS → 0…1), newest on the right, with the held peak as a thin marker.
/// Reads `SF2LevelMeter` (lock-free drain of the render thread's accumulator) from a 30 Hz
/// `TimelineView`; stops ticking ~2.5 s after playback stops.
struct LevelMeterView: View {
    let meter: SF2LevelMeter
    var active: Bool
    var barCount = 40

    @State private var decaying = false
    @State private var history = LevelHistory()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active && !decaying)) { ctx in
            let lv = meter.update(now: ctx.date.timeIntervalSinceReferenceDate)
            let bars = history.push(SF2LevelMath.fraction(db: max(lv.rmsL, lv.rmsR)), capacity: barCount)
            let peak = CGFloat(SF2LevelMath.fraction(db: max(lv.peakL, lv.peakR)))
            GeometryReader { geo in
                let w = geo.size.width / CGFloat(barCount)
                ZStack(alignment: .bottom) {
                    HStack(alignment: .center, spacing: 0) {
                        ForEach(0 ..< barCount, id: \.self) { i in
                            let f = CGFloat(i < bars.count ? bars[i] : 0)
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.coral.opacity(0.55), Theme.coral], startPoint: .bottom, endPoint: .top))
                                .frame(width: max(1, w * 0.55), height: max(3, f * geo.size.height))
                                .frame(width: w, height: geo.size.height)
                        }
                    }
                    Rectangle()
                        .fill(Theme.coralDeep.opacity(peak > 0 ? 0.6 : 0))
                        .frame(height: 1.5)
                        .offset(y: -peak * geo.size.height)
                }
            }
            .frame(height: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Output level")
            .accessibilityValue(Self.accessibilityValue(lv))
        }
        .task(id: active) {
            guard !active else { decaying = false; return }
            decaying = true
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled { decaying = false }
        }
        .accessibilityIdentifier("player.levelMeter")
    }

    static func accessibilityValue(_ lv: SF2MeterLevels) -> String {
        lv.isSilent ? "silent" : String(format: "peak %.0f dB", max(lv.peakL, lv.peakR))
    }
}

/// Fixed-size history of bar heights (0…1), oldest first. Reference type so the TimelineView
/// closure can append without triggering a SwiftUI state update.
final class LevelHistory {
    private(set) var values: [Float] = []

    @discardableResult
    func push(_ v: Float, capacity: Int) -> [Float] {
        values.append(min(1, max(0, v.isFinite ? v : 0)))
        if values.count > capacity { values.removeFirst(values.count - capacity) }
        if values.count < capacity { return [Float](repeating: 0, count: capacity - values.count) + values }
        return values
    }
}
