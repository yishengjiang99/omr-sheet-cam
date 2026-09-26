import SF2Player
import SwiftUI

/// Live stereo output meter: RMS bars + held peak ticks, drawn from `SF2LevelMeter` (lock-free
/// reads of the render thread's accumulator) at ~30 Hz. Stops ticking ~2.5 s after playback
/// stops, once the bars have fallen to the floor.
struct LevelMeterView: View {
    let meter: SF2LevelMeter
    var active: Bool

    @State private var decaying = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active && !decaying)) { ctx in
            let lv = meter.update(now: ctx.date.timeIntervalSinceReferenceDate)
            VStack(alignment: .leading, spacing: 4) {
                MeterBar(label: "L", rms: lv.rmsL, peak: lv.peakL)
                MeterBar(label: "R", rms: lv.rmsR, peak: lv.peakR)
                HStack {
                    Text("−60").frame(maxWidth: .infinity, alignment: .leading)
                    Text("−30")
                    Text("0 dBFS").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            }
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

private struct MeterBar: View {
    let label: String
    let rms: Float
    let peak: Float

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2.monospaced()).foregroundStyle(.secondary).frame(width: 10)
            GeometryReader { geo in
                let w = geo.size.width
                let fill = CGFloat(SF2LevelMath.fraction(db: rms)) * w
                let tick = CGFloat(SF2LevelMath.fraction(db: peak)) * w
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    LinearGradient(colors: [.green, .green, .yellow, .red], startPoint: .leading, endPoint: .trailing)
                        .frame(width: w)
                        .mask(alignment: .leading) { Rectangle().frame(width: fill) }
                        .clipShape(Capsule())
                    if peak > SF2LevelMath.floorDB {
                        Rectangle()
                            .fill(peak > -1 ? Color.red : Color.primary.opacity(0.8))
                            .frame(width: 2)
                            .offset(x: max(0, tick - 2))
                    }
                }
            }
            .frame(height: 8)
        }
    }
}
