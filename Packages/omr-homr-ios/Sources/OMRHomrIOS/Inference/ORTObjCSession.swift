// Apple (iOS / macOS) `ORTSessionBackend` over onnxruntime-objc.
//
// DEPRECATED (2026-09-26): iOS now uses `ORTCSession` over the ORT C API (CONNXRuntimeApple), which
// binds float16 via ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16. Kept behind `#if` until the Apple build
// of `ORTCSession` is verified on macOS CI; do not add new callers.
//
// UNVERIFIED: written against onnxruntime `objectivec/include/*.h` (main, ORT SPM 1.24.x) but
// never compiled here (Linux box). Module is `OnnxRuntimeBindings` via SwiftPM
// (microsoft/onnxruntime-swift-package-manager) or `onnxruntime_objc` via CocoaPods.
//
// Known gap: the Objective-C API's `ORTTensorElementDataType` has NO float16 case, so this
// backend cannot bind fp16 tensors. It throws `ORTObjCSessionError.unsupportedElementType`
// for `.float16` rather than reinterpret bytes. The pinned encoder is fp16 → see README
// ("ORT backends") for the open decision.
#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#elseif canImport(onnxruntime_objc)
import onnxruntime_objc
#endif

#if canImport(OnnxRuntimeBindings) || canImport(onnxruntime_objc)
import Foundation

public enum ORTObjCSessionError: Error, CustomStringConvertible {
    case unsupportedElementType(String)
    case missingOutput(String)

    public var description: String {
        switch self {
        case .unsupportedElementType(let m): return "ORTObjCSession unsupported element type: \(m)"
        case .missingOutput(let m): return "ORTObjCSession missing output: \(m)"
        }
    }
}

@available(*, deprecated, message: "onnxruntime-objc cannot bind float16; use ORTCSession (ORT C API) on iOS/macOS")
public final class ORTObjCSession: ORTSessionBackend, ORTProviderReporting {
    /// One process-wide ORT environment.
    private static let sharedEnv: Result<ORTEnv, Error> = Result {
        try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
    }

    private let session: ORTSession
    public let provider: ORTProvider
    public let inputNames: [String]
    public let outputNames: [String]

    /// - `.cpu`: default CPU EP only (the decoder's only allowed provider).
    /// - `.coreML`: CoreML EP (MLProgram, CPUAndGPU like upstream `coreml_mlprogram_providers`)
    ///   appended first; ORT keeps the CPU EP as fallback for nodes CoreML cannot take.
    public required init(modelURL: URL, provider: ORTProvider) throws {
        let env = try Self.sharedEnv.get()
        let options = try ORTSessionOptions()
        switch provider {
        case .cpu:
            break
        case .coreML:
            try options.appendCoreMLExecutionProvider(withOptionsV2: [
                "ModelFormat": "MLProgram",
                "MLComputeUnits": "CPUAndGPU",
            ])
        }
        self.session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: options)
        self.provider = provider
        self.inputNames = try session.inputNames()
        self.outputNames = try session.outputNames()
    }

    public func run(inputs: [String: ORTTensor], outputNames: [String]) throws -> [String: ORTTensor] {
        var feeds: [String: ORTValue] = [:]
        for (name, t) in inputs {
            feeds[name] = try ORTValue(
                tensorData: NSMutableData(data: t.data),
                elementType: try Self.objcType(t.type),
                shape: t.shape.map { NSNumber(value: $0) }
            )
        }
        let out = try session.run(withInputs: feeds, outputNames: Set(outputNames), runOptions: nil)
        var result: [String: ORTTensor] = [:]
        for name in outputNames {
            guard let value = out[name] else { throw ORTObjCSessionError.missingOutput(name) }
            let info = try value.tensorTypeAndShapeInfo()
            let data = try value.tensorData() as Data
            result[name] = ORTTensor(
                type: try Self.neutralType(info.elementType),
                shape: info.shape.map { $0.intValue },
                data: data
            )
        }
        return result
    }

    static func objcType(_ t: ORTElementType) throws -> ORTTensorElementDataType {
        switch t {
        case .float32: return .float
        case .int64: return .int64
        case .int32: return .int32
        case .float16:
            throw ORTObjCSessionError.unsupportedElementType(
                "float16 (onnxruntime-objc has no ORTTensorElementDataTypeFloat16)"
            )
        }
    }

    static func neutralType(_ t: ORTTensorElementDataType) throws -> ORTElementType {
        switch t {
        case .float: return .float32
        case .int64: return .int64
        case .int32: return .int32
        default: throw ORTObjCSessionError.unsupportedElementType("ORT element type raw \(t.rawValue)")
        }
    }
}
#endif
