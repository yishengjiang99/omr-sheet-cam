import Foundation

// Backend-neutral ONNX Runtime seam.
//
// Conformers:
// - iOS / macOS: `ORTObjCSession` (onnxruntime-objc), behind `#if canImport(onnxruntime_objc)`.
// - Linux: `ORTCSession` (ORT C API wrapper, app-side branch `ios/ort-c-linux`).
//
// Backends move RAW bytes only (little-endian, row-major, element type as tagged). They never
// convert dtypes: the single fp16 → fp32 cast lives in `EncoderContext.castToFP32ForDecoder()`.
//
// Locked provider rules (enforced by the sessions, not the backend):
// - Encoder / SegNet: `.coreML` (fp16) with CPU fallback on iOS; `.cpu` elsewhere.
// - Decoder: fp32, `.cpu` ONLY on every platform — `DecoderSession` rejects anything else.

public enum ORTElementType: Sendable { case float32, float16, int64, int32 }

public enum ORTProvider: Sendable { case cpu, coreML }

public struct ORTTensor: Sendable {
    public var type: ORTElementType
    public var shape: [Int]
    public var data: Data
    public init(type: ORTElementType, shape: [Int], data: Data) {
        self.type = type
        self.shape = shape
        self.data = data
    }
}

public protocol ORTSessionBackend: AnyObject {
    init(modelURL: URL, provider: ORTProvider) throws
    var inputNames: [String] { get }
    var outputNames: [String] { get }
    func run(inputs: [String: ORTTensor], outputNames: [String]) throws -> [String: ORTTensor]
}
