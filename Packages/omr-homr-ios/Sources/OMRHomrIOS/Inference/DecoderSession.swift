import Foundation

/// Decoder session wiring stub.
///
/// Product rule: Decoder runs on ORT **CPU only**, **fp32**.
/// Never GPU / WebGPU / Metal / CoreML for the decoder.
/// Do not requantize the published decoder checkpoint.
///
/// TODO(gate-1): Attach ORT Swift `CPUExecutionProvider` to bundled Decoder fp32 ONNX.
public final class DecoderSession: @unchecked Sendable {
    public let vocabulary: HomrVocabulary
    public let modelURL: URL?
    public private(set) var isConfigured: Bool

    /// Locked: CPU only.
    public let executionProvider = "CPUExecutionProvider"

    public init(vocabulary: HomrVocabulary, modelURL: URL? = nil) {
        self.vocabulary = vocabulary
        self.modelURL = modelURL
        self.isConfigured = false
    }

    public func configureStub() throws {
        guard let modelURL else {
            throw OMRError.modelsNotBundled(
                "Decoder fp32 ONNX not bundled. Download from liebharc/homr releases tag onnx_checkpoints. Do not requantize."
            )
        }
        _ = modelURL
        // TODO: ort.InferenceSession(path, providers: [CPUExecutionProvider only])
        throw OMRError.sessionNotConfigured(
            "ORT CPU binding not yet linked; decoder configure is a scaffold stub"
        )
    }

    /// One decoder step inputs/outputs names — mirrors `decoder_inference.py`.
    public static let inputNames = [
        "rhythms", "pitchs", "lifts", "articulations", "slurs", "context", "cache_len",
    ]
    public static let outputNames = [
        "out_rhythms", "out_pitchs", "out_lifts", "out_positions",
        "out_articulations", "out_slurs", "attention",
    ]

    /// Config knobs mirrored from `homr.transformer.configs.Config`.
    public var decoderDepth: Int { 8 }
    public var decoderHeads: Int { 8 }
    public var decoderDim: Int { 512 }
}
