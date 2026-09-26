import Foundation

/// Staff-only inference orchestration for gate-1.
///
/// Pipeline (locked): Encoder fp16 CoreML EP → cast fp16→fp32 → Decoder fp32 ORT CPU
/// → symbols → SMF + noteLayout.
///
/// SegNet tiling / full-page geometry are explicitly out of scope here.
public final class StaffInferenceSession: @unchecked Sendable {
    public let vocabulary: HomrVocabulary
    public let encoder: EncoderSession
    public let decoder: DecoderSession
    public let decoderLoop: DecoderLoop
    public let smfWriter: SMFWriter

    public init(
        vocabulary: HomrVocabulary,
        encoder: EncoderSession,
        decoder: DecoderSession,
        smfWriter: SMFWriter = SMFWriter()
    ) {
        self.vocabulary = vocabulary
        self.encoder = encoder
        self.decoder = decoder
        self.decoderLoop = DecoderLoop(vocabulary: vocabulary)
        self.smfWriter = smfWriter
    }

    /// Default scaffold: load vocab + HF tokenizer presence check; models optional/missing.
    public static func makeDefault(bundle: Bundle = .module) throws -> StaffInferenceSession {
        let vocab = try TokenizerLoader.loadVocabulary(bundle: bundle)
        _ = try TokenizerLoader.requireHFTokenizerAssets(bundle: bundle)
        let encoder = EncoderSession(modelURL: nil)
        let decoder = DecoderSession(vocabulary: vocab, modelURL: nil)
        return StaffInferenceSession(vocabulary: vocab, encoder: encoder, decoder: decoder)
    }

    public func parse(input: ParseSheetMusicInput) throws -> ParseSheetMusicResult {
        guard input.staffOnly else {
            throw OMRError.staffOnlyGate1NotReady(
                "Full-page / SegNet path is out of scope for gate-1; set staffOnly=true"
            )
        }
        guard !input.imageData.isEmpty else {
            throw OMRError.staffOnlyGate1NotReady("Empty staff imageData")
        }

        // Intentionally do not fake model runs.
        throw OMRError.staffOnlyGate1NotReady(
            """
            Gate-1 scaffold: tokenizer + SMF hooks ready; encoder/decoder ORT sessions and \
            C-scale oracle fixtures not yet wired. Stop condition is staff-only C-scale oracle \
            token match before UI/geometry work.
            """
        )
    }

    /// Hook for oracle-driven token compare once fixtures land.
    public func decodeStaffSymbols(
        normalizedStaffImage: Data,
        stepRunner: DecoderStepRunning
    ) throws -> [EncodedSymbol] {
        let context = try encoder.generateContext(staffImageNormalized: normalizedStaffImage)
        let fp32 = context.castToFP32ForDecoder()
        return try decoderLoop.generate(context: fp32, stepRunner: stepRunner)
    }
}
