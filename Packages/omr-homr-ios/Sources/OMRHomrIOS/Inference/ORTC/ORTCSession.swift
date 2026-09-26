#if canImport(CONNXRuntime)
internal import CONNXRuntime
import Foundation

// Linux ONNX Runtime C-API backend for `ORTSessionBackend` (see ORTBackend.swift).
//
// - CPU execution provider ONLY: no execution provider is ever appended to the session options,
//   so ORT runs everything on its default CPU EP. `init` throws for any provider other than `.cpu`.
// - Moves RAW little-endian, row-major bytes tagged with their element type (float32, float16,
//   int64, int32). It never converts dtypes; the single fp16 -> fp32 cast lives in
//   `EncoderContext.castToFP32ForDecoder()`.
// - Built only on Linux when scripts/fetch-ort has installed third_party/onnxruntime
//   (Package.swift adds the `CONNXRuntime` system library). iOS keeps onnxruntime-objc + CoreML.

/// Errors raised by `ORTCSession`.
public enum ORTCError: Error, CustomStringConvertible, Sendable {
    /// Linux C-API backend is CPU-only; `.coreML` (or anything else) is rejected.
    case unsupportedProvider(String)
    /// `OrtGetApiBase()->GetApi(ORT_API_VERSION)` returned NULL (header/library mismatch).
    case apiUnavailable(requested: Int, library: String)
    /// An `OrtStatus` error returned by the C API.
    case ort(code: Int, message: String, call: String)
    /// Input/output tensor does not match its declared shape or element type.
    case invalidTensor(String)
    /// Model uses an element type outside float32/float16/int64/int32.
    case unsupportedElementType(name: String, onnxType: Int)
    /// Requested input/output name is not part of the model.
    case unknownName(String)

    public var description: String {
        switch self {
        case let .unsupportedProvider(p): return "ORTCSession: provider \(p) not supported on Linux (CPU EP only)"
        case let .apiUnavailable(v, lib): return "ORTCSession: ORT C API v\(v) unavailable in libonnxruntime \(lib)"
        case let .ort(code, msg, call): return "ORTCSession: \(call) failed (OrtErrorCode \(code)): \(msg)"
        case let .invalidTensor(m): return "ORTCSession: invalid tensor: \(m)"
        case let .unsupportedElementType(n, t): return "ORTCSession: '\(n)' has unsupported ONNX element type \(t)"
        case let .unknownName(n): return "ORTCSession: unknown input/output name '\(n)'"
        }
    }
}

/// Process-wide ORT API table + `OrtEnv` (ORT recommends one env per process).
private final class ORTCRuntime: @unchecked Sendable {
    let api: OrtApi
    let env: OpaquePointer

    static let shared: Result<ORTCRuntime, Error> = Result { try ORTCRuntime() }

    private init() throws {
        guard let base = OrtGetApiBase() else {
            throw ORTCError.apiUnavailable(requested: Int(ORT_API_VERSION), library: "?")
        }
        let libVersion = base.pointee.GetVersionString.flatMap { $0() }.map { String(cString: $0) } ?? "?"
        guard let apiPtr = base.pointee.GetApi!(UInt32(ORT_API_VERSION)) else {
            throw ORTCError.apiUnavailable(requested: Int(ORT_API_VERSION), library: libVersion)
        }
        api = apiPtr.pointee
        var envOut: OpaquePointer?
        try ORTCRuntime.check(api, api.CreateEnv!(ORT_LOGGING_LEVEL_WARNING, "omr-ortc", &envOut), "CreateEnv")
        guard let envOut else { throw ORTCError.ort(code: -1, message: "null OrtEnv", call: "CreateEnv") }
        env = envOut
        // Intentionally never released: lives for the process, shared by all sessions.
    }

    /// Converts a non-NULL `OrtStatus*` into a thrown `ORTCError.ort`, releasing the status.
    static func check(_ api: OrtApi, _ status: OpaquePointer?, _ call: String) throws {
        guard let status else { return }
        let message = api.GetErrorMessage!(status).map { String(cString: $0) } ?? "unknown error"
        let code = Int(api.GetErrorCode!(status).rawValue)
        api.ReleaseStatus!(status)
        throw ORTCError.ort(code: code, message: message, call: call)
    }
}

/// ONNX Runtime session via the C API, CPU execution provider only.
///
/// ```swift
/// let dec = try ORTCSession(modelURL: decoderURL, provider: .cpu)
/// let out = try dec.run(inputs: ["rhythms": ORTTensor(type: .int64, shape: [1, 1], data: ...), ...],
///                       outputNames: ["out_rhythms"])
/// ```
public final class ORTCSession: ORTSessionBackend, @unchecked Sendable {
    /// Declared model input/output (ONNX metadata). Dynamic dims are `-1` in `shape`,
    /// with their symbolic name (if any) in `symbolicShape`.
    public struct IOInfo: Sendable, CustomStringConvertible {
        public let name: String
        /// `nil` when the model declares a type outside float32/float16/int64/int32.
        public let elementType: ORTElementType?
        /// Raw `ONNXTensorElementDataType` value (1 = float, 10 = float16, 7 = int64, 6 = int32, ...).
        public let onnxElementType: Int
        public let shape: [Int]
        public let symbolicShape: [String]

        public var description: String {
            let dims = zip(shape, symbolicShape).map { d, s in d >= 0 ? String(d) : (s.isEmpty ? "?" : s) }
            let t = elementType.map { "\($0)" } ?? "onnx#\(onnxElementType)"
            return "\(name): \(t) [\(dims.joined(separator: ", "))]"
        }
    }

    public let modelURL: URL
    /// Always `.cpu` (enforced in `init`).
    public let provider: ORTProvider
    public let inputNames: [String]
    public let outputNames: [String]
    public let inputInfo: [IOInfo]
    public let outputInfo: [IOInfo]

    private let runtime: ORTCRuntime
    private let session: OpaquePointer
    private let memoryInfo: OpaquePointer

    /// `libonnxruntime` version string, e.g. "1.24.2".
    public static var runtimeVersion: String {
        guard let base = OrtGetApiBase(), let f = base.pointee.GetVersionString else { return "?" }
        return f().map { String(cString: $0) } ?? "?"
    }

    /// Intra-op threads used by `init(modelURL:provider:)`: `OMR_ORT_INTRA_OP_THREADS` if set, else 1.
    ///
    /// Default is 1 for determinism: with ORT's default multi-threaded intra-op pool the homr decoder
    /// gave run-to-run different logits for identical inputs (seen in Swift and in Python ORT 1.30),
    /// which breaks exact-token oracle gates. Single-threaded runs matched Python homr exactly.
    public static var defaultIntraOpThreads: Int {
        ProcessInfo.processInfo.environment["OMR_ORT_INTRA_OP_THREADS"].flatMap { Int($0) } ?? 1
    }

    /// `ORTSessionBackend` entry point. Throws unless `provider == .cpu`.
    public convenience init(modelURL: URL, provider: ORTProvider) throws {
        try self.init(modelURL: modelURL, provider: provider, intraOpThreads: Self.defaultIntraOpThreads)
    }

    /// - Parameter intraOpThreads: 0 = ORT default pool (one per physical core; NOT run-to-run
    ///   deterministic for the homr decoder), 1 = deterministic single-threaded.
    public init(modelURL: URL, provider: ORTProvider, intraOpThreads: Int) throws {
        guard case .cpu = provider else {
            throw ORTCError.unsupportedProvider("\(provider)")
        }
        let runtime = try ORTCRuntime.shared.get()
        let api = runtime.api
        self.runtime = runtime
        self.modelURL = modelURL
        self.provider = .cpu

        var options: OpaquePointer?
        try ORTCRuntime.check(api, api.CreateSessionOptions!(&options), "CreateSessionOptions")
        defer { if let options { api.ReleaseSessionOptions!(options) } }
        try ORTCRuntime.check(api, api.SetIntraOpNumThreads!(options, Int32(intraOpThreads)), "SetIntraOpNumThreads")
        try ORTCRuntime.check(
            api, api.SetSessionGraphOptimizationLevel!(options, ORT_ENABLE_ALL), "SetSessionGraphOptimizationLevel"
        )
        // CPU EP only: deliberately NO SessionOptionsAppendExecutionProvider* call of any kind.

        var sessionOut: OpaquePointer?
        try ORTCRuntime.check(
            api,
            modelURL.path.withCString { api.CreateSession!(runtime.env, $0, options, &sessionOut) },
            "CreateSession(\(modelURL.lastPathComponent))"
        )
        guard let sessionOut else { throw ORTCError.ort(code: -1, message: "null OrtSession", call: "CreateSession") }

        var mem: OpaquePointer?
        let memStatus = api.CreateCpuMemoryInfo!(OrtArenaAllocator, OrtMemTypeDefault, &mem)
        if memStatus != nil || mem == nil {
            api.ReleaseSession!(sessionOut)
            try ORTCRuntime.check(api, memStatus, "CreateCpuMemoryInfo")
            throw ORTCError.ort(code: -1, message: "null OrtMemoryInfo", call: "CreateCpuMemoryInfo")
        }

        do {
            let ins = try Self.describe(api: api, session: sessionOut, inputs: true)
            let outs = try Self.describe(api: api, session: sessionOut, inputs: false)
            self.inputInfo = ins
            self.outputInfo = outs
            self.inputNames = ins.map(\.name)
            self.outputNames = outs.map(\.name)
        } catch {
            api.ReleaseMemoryInfo!(mem)
            api.ReleaseSession!(sessionOut)
            throw error
        }
        self.session = sessionOut
        self.memoryInfo = mem!
    }

    deinit {
        runtime.api.ReleaseMemoryInfo!(memoryInfo)
        runtime.api.ReleaseSession!(session)
    }

    /// Runs the model. `inputs` must cover every model input. `outputNames` empty = all outputs.
    /// Returns raw output bytes keyed by name (fp16 stays fp16 — no casting here).
    public func run(inputs: [String: ORTTensor], outputNames requested: [String]) throws -> [String: ORTTensor] {
        let api = runtime.api
        let wanted = requested.isEmpty ? outputNames : requested
        for name in wanted where !outputNames.contains(name) { throw ORTCError.unknownName(name) }
        for name in inputs.keys where !inputNames.contains(name) { throw ORTCError.unknownName(name) }

        // Stable order: model input order.
        let ordered: [(String, ORTTensor)] = try inputNames.map { name in
            guard let t = inputs[name] else { throw ORTCError.invalidTensor("missing input '\(name)'") }
            return (name, t)
        }

        var buffers: [UnsafeMutableRawPointer] = []
        var values: [OpaquePointer?] = []
        var cInputNames: [UnsafeMutablePointer<CChar>?] = []
        var cOutputNames: [UnsafeMutablePointer<CChar>?] = wanted.map { strdup($0) }
        var outValues = [OpaquePointer?](repeating: nil, count: wanted.count)
        defer {
            for v in values { if let v { api.ReleaseValue!(v) } }
            for v in outValues { if let v { api.ReleaseValue!(v) } }
            for b in buffers { b.deallocate() }
            for p in cInputNames { free(p) }
            for p in cOutputNames { free(p) }
        }

        for (name, tensor) in ordered {
            let elemSize = Self.byteSize(tensor.type)
            guard tensor.shape.allSatisfy({ $0 >= 0 }) else {
                throw ORTCError.invalidTensor("'\(name)' has negative dim in \(tensor.shape)")
            }
            let count = tensor.shape.reduce(1, *)
            guard tensor.data.count == count * elemSize else {
                throw ORTCError.invalidTensor(
                    "'\(name)' shape \(tensor.shape) \(tensor.type) needs \(count * elemSize) bytes, got \(tensor.data.count)"
                )
            }
            // ORT does not copy user buffers: keep an owned, aligned copy alive until Run returns.
            let byteCount = max(tensor.data.count, 1)
            let buf = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 16)
            buffers.append(buf)
            tensor.data.withUnsafeBytes { src in
                if let base = src.baseAddress, src.count > 0 { buf.copyMemory(from: base, byteCount: src.count) }
            }
            var dims = tensor.shape.map { Int64($0) }
            var value: OpaquePointer?
            let status = dims.withUnsafeMutableBufferPointer { d in
                api.CreateTensorWithDataAsOrtValue!(
                    memoryInfo, buf, tensor.data.count, d.baseAddress, d.count, Self.onnxType(tensor.type), &value
                )
            }
            try ORTCRuntime.check(api, status, "CreateTensorWithDataAsOrtValue(\(name))")
            values.append(value)
            cInputNames.append(strdup(name))
        }

        let runStatus: OpaquePointer? = cInputNames.withUnsafeBufferPointer { inNamesBuf in
            cOutputNames.withUnsafeMutableBufferPointer { outNamesBuf in
                values.withUnsafeBufferPointer { valuesBuf in
                    outValues.withUnsafeMutableBufferPointer { outBuf in
                        inNamesBuf.baseAddress!.withMemoryRebound(
                            to: UnsafePointer<CChar>?.self, capacity: inNamesBuf.count
                        ) { inNames in
                            outNamesBuf.baseAddress!.withMemoryRebound(
                                to: UnsafePointer<CChar>?.self, capacity: outNamesBuf.count
                            ) { outNames in
                                api.Run!(
                                    session, nil,
                                    inNames, valuesBuf.baseAddress, valuesBuf.count,
                                    outNames, outBuf.count, outBuf.baseAddress
                                )
                            }
                        }
                    }
                }
            }
        }
        try ORTCRuntime.check(api, runStatus, "Run")

        var result: [String: ORTTensor] = [:]
        for (i, name) in wanted.enumerated() {
            guard let value = outValues[i] else { throw ORTCError.invalidTensor("null output '\(name)'") }
            result[name] = try Self.readTensor(api: api, value: value, name: name)
        }
        return result
    }

    // MARK: - Helpers

    /// Bytes per element for `type`.
    public static func byteSize(_ type: ORTElementType) -> Int {
        switch type {
        case .float32, .int32: return 4
        case .float16: return 2
        case .int64: return 8
        }
    }

    private static func onnxType(_ type: ORTElementType) -> ONNXTensorElementDataType {
        switch type {
        case .float32: return ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT
        case .float16: return ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16
        case .int64: return ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64
        case .int32: return ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32
        }
    }

    private static func elementType(_ t: ONNXTensorElementDataType) -> ORTElementType? {
        switch t {
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT: return .float32
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16: return .float16
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64: return .int64
        case ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32: return .int32
        default: return nil
        }
    }

    private static func readTensor(api: OrtApi, value: OpaquePointer, name: String) throws -> ORTTensor {
        var info: OpaquePointer?
        try ORTCRuntime.check(api, api.GetTensorTypeAndShape!(value, &info), "GetTensorTypeAndShape(\(name))")
        defer { if let info { api.ReleaseTensorTypeAndShapeInfo!(info) } }
        var onnx = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED
        try ORTCRuntime.check(api, api.GetTensorElementType!(info, &onnx), "GetTensorElementType(\(name))")
        guard let type = elementType(onnx) else {
            throw ORTCError.unsupportedElementType(name: name, onnxType: Int(onnx.rawValue))
        }
        var rank = 0
        try ORTCRuntime.check(api, api.GetDimensionsCount!(info, &rank), "GetDimensionsCount(\(name))")
        var dims = [Int64](repeating: 0, count: rank)
        if rank > 0 {
            try ORTCRuntime.check(api, api.GetDimensions!(info, &dims, rank), "GetDimensions(\(name))")
        }
        let shape = dims.map { Int($0) }
        let byteCount = shape.reduce(1, *) * byteSize(type)
        var raw: UnsafeMutableRawPointer?
        try ORTCRuntime.check(api, api.GetTensorMutableData!(value, &raw), "GetTensorMutableData(\(name))")
        let data: Data
        if byteCount == 0 {
            data = Data()
        } else if let raw {
            data = Data(bytes: raw, count: byteCount)
        } else {
            throw ORTCError.invalidTensor("null data for output '\(name)'")
        }
        return ORTTensor(type: type, shape: shape, data: data)
    }

    private static func describe(api: OrtApi, session: OpaquePointer, inputs: Bool) throws -> [IOInfo] {
        var allocator: UnsafeMutablePointer<OrtAllocator>?
        try ORTCRuntime.check(api, api.GetAllocatorWithDefaultOptions!(&allocator), "GetAllocatorWithDefaultOptions")
        var count = 0
        try ORTCRuntime.check(
            api,
            inputs ? api.SessionGetInputCount!(session, &count) : api.SessionGetOutputCount!(session, &count),
            "SessionGet\(inputs ? "Input" : "Output")Count"
        )
        var result: [IOInfo] = []
        for i in 0..<count {
            var cName: UnsafeMutablePointer<CChar>?
            try ORTCRuntime.check(
                api,
                inputs
                    ? api.SessionGetInputName!(session, i, allocator, &cName)
                    : api.SessionGetOutputName!(session, i, allocator, &cName),
                "SessionGet\(inputs ? "Input" : "Output")Name"
            )
            let name = cName.map { String(cString: $0) } ?? ""
            if let cName { _ = api.AllocatorFree!(allocator, cName) }

            var typeInfo: OpaquePointer?
            try ORTCRuntime.check(
                api,
                inputs
                    ? api.SessionGetInputTypeInfo!(session, i, &typeInfo)
                    : api.SessionGetOutputTypeInfo!(session, i, &typeInfo),
                "SessionGet\(inputs ? "Input" : "Output")TypeInfo(\(name))"
            )
            defer { if let typeInfo { api.ReleaseTypeInfo!(typeInfo) } }
            var tensorInfo: OpaquePointer?
            try ORTCRuntime.check(api, api.CastTypeInfoToTensorInfo!(typeInfo, &tensorInfo), "CastTypeInfoToTensorInfo")
            guard let tensorInfo else {
                // Non-tensor (sequence/map) I/O: report as unsupported type with no shape.
                result.append(IOInfo(name: name, elementType: nil, onnxElementType: 0, shape: [], symbolicShape: []))
                continue
            }
            var onnx = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED
            try ORTCRuntime.check(api, api.GetTensorElementType!(tensorInfo, &onnx), "GetTensorElementType")
            var rank = 0
            try ORTCRuntime.check(api, api.GetDimensionsCount!(tensorInfo, &rank), "GetDimensionsCount")
            var dims = [Int64](repeating: 0, count: rank)
            var symbols = [UnsafePointer<CChar>?](repeating: nil, count: rank)
            if rank > 0 {
                try ORTCRuntime.check(api, api.GetDimensions!(tensorInfo, &dims, rank), "GetDimensions")
                try ORTCRuntime.check(api, api.GetSymbolicDimensions!(tensorInfo, &symbols, rank), "GetSymbolicDimensions")
            }
            result.append(
                IOInfo(
                    name: name,
                    elementType: elementType(onnx),
                    onnxElementType: Int(onnx.rawValue),
                    shape: dims.map { Int($0) },
                    symbolicShape: symbols.map { $0.map { String(cString: $0) } ?? "" }
                )
            )
        }
        return result
    }
}
#endif
