import Foundation

/// Encoder session wiring stub.
///
/// Product rule: Encoder runs **fp16 CoreML EP** with CPU fallback.
/// Do not attach Metal/GPU providers here for the decoder path.
///
/// Staff-only Gate-1 input: NCHW `[1,1,256,1280]` float tile after
/// `StaffInputSpec` normalize (see `staff2score.ConvertToArray`).
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

    /// Staff image → encoder context tensor (fp16 when CoreML EP is active).
    ///
    /// - Parameter staffImageNormalized: Preprocessed NCHW bytes matching
    ///   `StaffInputSpec` (fp32 normalize → cast to encoder dtype at bind time).
    public func generateContext(staffImageNormalized _: Data) throws -> EncoderContext {
        throw OMRError.sessionNotConfigured(
            "EncoderSession.generateContext requires ORT CoreML EP binding (scaffold); expected staff NCHW \(StaffInputSpec.nchwShape)"
        )
    }
}

/// Opaque encoder context handed to the decoder after fp16→fp32 cast when needed.
///
/// Mirrors `staff2score.py`:
/// ```
/// context = encoder.generate(x)
/// context_dtype = float16 if decoder.fp16 else float32
/// if context.dtype != context_dtype: context = context.astype(context_dtype)
/// ```
/// Locked product path: Decoder is fp32 CPU → always cast fp16→fp32 here.
public struct EncoderContext: Sendable {
    public var bytes: Data
    public var dtype: ContextDType
    /// Logical shape e.g. `[1, seq, dim]` — filled when ORT binding lands.
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
    ///
    /// When `bytes` hold IEEE754 binary16 little-endian values, widens each
    /// element to binary32. Empty / already-fp32 contexts pass through.
    public func castToFP32ForDecoder() -> EncoderContext {
        guard dtype == .float16 else { return self }
        guard !bytes.isEmpty else {
            return EncoderContext(bytes: bytes, dtype: .float32, shape: shape)
        }
        guard bytes.count % 2 == 0 else {
            // Malformed half buffer — keep dtype marker honest; ORT bind will fail loudly later.
            return EncoderContext(bytes: bytes, dtype: .float32, shape: shape)
        }
        let halfCount = bytes.count / 2
        var out = [Float]()
        out.reserveCapacity(halfCount)
        bytes.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: UInt16.self)
            for i in 0..<halfCount {
                out.append(Self.float32(fromFloat16Bits: src[i]))
            }
        }
        var outData = Data(count: halfCount * MemoryLayout<Float>.size)
        outData.withUnsafeMutableBytes { dst in
            out.withUnsafeBytes { src in
                dst.copyMemory(from: src)
            }
        }
        return EncoderContext(bytes: outData, dtype: .float32, shape: shape)
    }

    /// IEEE754 binary16 → Float (matches NumPy `astype(float32)` for finite values).
    static func float32(fromFloat16Bits bits: UInt16) -> Float {
        let sign = UInt32((bits & 0x8000) >> 15)
        let exp = Int((bits & 0x7C00) >> 10)
        let frac = UInt32(bits & 0x03FF)

        let sign32 = sign << 31
        if exp == 0 {
            if frac == 0 {
                return Float(bitPattern: sign32)
            }
            // Subnormal half → normalized float
            var f = frac
            var e = -14 + 127
            while f & 0x0400 == 0 {
                f <<= 1
                e -= 1
            }
            f &= 0x03FF
            let bits32 = sign32 | (UInt32(e) << 23) | (f << 13)
            return Float(bitPattern: bits32)
        }
        if exp == 0x1F {
            // Inf / NaN
            let bits32 = sign32 | 0x7F800000 | (frac << 13)
            return Float(bitPattern: bits32)
        }
        let exp32 = UInt32(exp - 15 + 127)
        let bits32 = sign32 | (exp32 << 23) | (frac << 13)
        return Float(bitPattern: bits32)
    }
}
