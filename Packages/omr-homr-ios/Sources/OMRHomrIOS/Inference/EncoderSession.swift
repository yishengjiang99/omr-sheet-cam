import Foundation

/// Encoder session wiring stub.
///
/// Product rule: Encoder runs **fp16 CoreML EP** with CPU fallback.
/// Do not attach Metal/GPU providers here for the decoder path.
///
/// TODO(gate-1+): Bind ONNX Runtime Swift session to bundled Encoder fp16 ONNX
/// with `CoreMLExecutionProvider` + `CPUExecutionProvider` fallback. Do not fake runs.
public final class EncoderSession: @unchecked Sendable {
    public enum ExecutionProvider: String, Sendable {
        case coreMLFP16 = "CoreML-fp16"
        case cpuFallback = "CPU-fallback"
    }

    public let preferredProvider: ExecutionProvider
    public private(set) var activeProvider: ExecutionProvider?
    public private(set) var isConfigured: Bool

    /// Model path once weights are bundled (Git LFS / release asset). Nil in scaffold.
    public let modelURL: URL?

    public init(modelURL: URL? = nil, preferredProvider: ExecutionProvider = .coreMLFP16) {
        self.modelURL = modelURL
        self.preferredProvider = preferredProvider
        self.activeProvider = nil
        self.isConfigured = false
    }

    /// Compile-safe stub: records intent; does not load ORT.
    public func configureStub() throws {
        guard let modelURL else {
            throw OMRError.modelsNotBundled(
                "Encoder fp16 ONNX not bundled. Download from liebharc/homr releases tag onnx_checkpoints."
            )
        }
        _ = modelURL
        // TODO: ort.InferenceSession(path, providers: [CoreML EP, CPU EP])
        throw OMRError.sessionNotConfigured(
            "ORT CoreML EP binding not yet linked; encoder configure is a scaffold stub"
        )
    }

    /// Staff image → encoder context tensor (fp16). Cast to fp32 before decoder.
    public func generateContext(staffImageNormalized _: Data) throws -> EncoderContext {
        throw OMRError.sessionNotConfigured(
            "EncoderSession.generateContext requires ORT CoreML EP binding (scaffold)"
        )
    }
}

/// Opaque encoder context handed to the decoder after fp16→fp32 cast when needed.
public struct EncoderContext: Sendable {
    public var bytes: Data
    public var dtype: ContextDType
    /// Logical shape e.g. [1, seq, dim] — filled when ORT binding lands.
    public var shape: [Int]

    public enum ContextDType: String, Sendable {
        case float16
        case float32
    }

    public init(bytes: Data, dtype: ContextDType, shape: [Int]) {
        self.bytes = bytes
        self.dtype = dtype
        self.shape = shape
    }

    /// Product rule: cast context fp16→fp32 before Decoder ORT CPU.
    public func castToFP32ForDecoder() -> EncoderContext {
        guard dtype == .float16 else { return self }
        // TODO: real half→float conversion when tensors are live.
        return EncoderContext(bytes: bytes, dtype: .float32, shape: shape)
    }
}
