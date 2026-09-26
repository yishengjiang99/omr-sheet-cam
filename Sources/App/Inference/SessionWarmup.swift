import Foundation
import OMRHomrIOS

/// Launch-time ORT / CoreML session warmup stub.
///
/// Product rules (locked):
/// - Encoder: CoreML EP (fp16) with CPU fallback — stub until models land
/// - Decoder: ORT **CPU only** (fp32) — never GPU/Metal/CoreML
/// - Do not commit ONNX weights; do not fake inference runs
///
/// Until `onnx_checkpoints` are bundled and ORT Swift bindings land in the
/// AGPL package, this is an intentional no-op that records status for the
/// Gate-1 debug surface.
enum SessionWarmup {
    private(set) static var lastStatus: String = "not run"
    private(set) static var didAttemptWarmup: Bool = false

    static var statusDescription: String { lastStatus }

    /// Call from `@main` init. Safe to invoke repeatedly.
    static func warmupAtLaunch() {
        didAttemptWarmup = true

        // Dummy tile placeholder — documents the future encoder preload path.
        // A real warmup would:
        //   1. Locate bundled Encoder fp16 + Decoder fp32 ONNX (not in repo yet)
        //   2. EncoderSession.configureStub() → CoreML EP + CPU fallback
        //   3. DecoderSession.configureStub() → CPUExecutionProvider only
        //   4. Run a 1×1 / tiny staff tile through encoder→cast fp16→fp32→decoder once
        // Package currently throws modelsNotBundled / sessionNotConfigured — swallow & report.
        var notes: [String] = []

        do {
            let session = try StaffInferenceSession.makeDefault()
            notes.append("vocab+tokenizers: OK")
            do {
                try session.encoder.configureStub()
                notes.append("encoder: configured")
            } catch let error as OMRError {
                notes.append("encoder: \(error) (expected until models)")
            }
            do {
                try session.decoder.configureStub()
                notes.append("decoder: configured")
            } catch let error as OMRError {
                notes.append("decoder: \(error) (expected until models)")
            }
        } catch let error as OMRError {
            notes.append("session: \(error)")
        } catch {
            notes.append("session: unexpected \(error)")
        }

        notes.append("dummy tile: skipped (no-op until ORT bindings)")
        lastStatus = notes.joined(separator: " | ")
    }
}
