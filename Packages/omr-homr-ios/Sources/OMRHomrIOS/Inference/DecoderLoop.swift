import Foundation

/// Staff-only decoder token loop structured to mirror
/// `homr/transformer/decoder_inference.py` `ScoreDecoder.generate`.
///
/// Gate-1 stop condition: C-scale staff oracle token match (fixture-driven).
/// This type holds the loop structure; ORT step execution is intentionally not faked.
public struct DecoderLoop: Sendable {
    public let vocabulary: HomrVocabulary

    public init(vocabulary: HomrVocabulary) {
        self.vocabulary = vocabulary
    }

    /// Mirrors Python `generate(start_tokens, nonote_tokens, context=...)`.
    ///
    /// - Parameters:
    ///   - startRhythmToken: BOS id (Config.bos_token == 1)
    ///   - nonoteToken: nonote id for pitch/lift/… streams (0)
    ///   - context: encoder context already cast to decoder dtype (fp32 on CPU path)
    ///   - stepRunner: injectible ORT step; scaffold throws until bound
    public func generate(
        startRhythmToken: Int? = nil,
        nonoteToken: Int? = nil,
        context: EncoderContext,
        stepRunner: DecoderStepRunning
    ) throws -> [EncodedSymbol] {
        let bos = startRhythmToken ?? vocabulary.bosToken
        let nonote = nonoteToken ?? vocabulary.nonoteToken
        _ = context // used when ORT binds real tensors

        var outRhythm: [Int] = [bos]
        var outPitch: [Int] = [nonote]
        var outLift: [Int] = [nonote]
        var outArticulations: [Int] = [nonote]
        var outSlurs: [Int] = [nonote]

        var symbols: [EncodedSymbol] = []
        let maxLen = vocabulary.maxSeqLen

        for step in 0..<maxLen {
            let xRhythm = outRhythm[outRhythm.count - 1]
            let xPitch = outPitch[outPitch.count - 1]
            let xLift = outLift[outLift.count - 1]
            let xArticulations = outArticulations[outArticulations.count - 1]
            let xSlurs = outSlurs[outSlurs.count - 1]

            // After first step, Python passes context_reduced = context[:, :1]
            let useFullContext = (step == 0)

            let stepOut = try stepRunner.runStep(
                DecoderStepInput(
                    stepIndex: step,
                    rhythm: xRhythm,
                    pitch: xPitch,
                    lift: xLift,
                    articulation: xArticulations,
                    slur: xSlurs,
                    useFullContext: useFullContext
                )
            )

            let rhythmSample = stepOut.rhythmArgmax
            let pitchSample = stepOut.pitchArgmax
            let liftSample = stepOut.liftArgmax
            let articulationSample = stepOut.articulationArgmax
            let slurSample = stepOut.slurArgmax
            let positionSample = stepOut.positionArgmax

            if rhythmSample == vocabulary.eosToken {
                break
            }

            let rhythmTok = Self.detokenize(rhythmSample, vocabulary.invRhythm)
            let pitchTok = Self.detokenize(pitchSample, vocabulary.invPitch)
            let liftTok = Self.detokenize(liftSample, vocabulary.invLift)
            let articulationTok = Self.detokenize(articulationSample, vocabulary.invArticulation)
            let slurTok = Self.detokenize(slurSample, vocabulary.invSlur)
            let positionTok = Self.detokenize(positionSample, vocabulary.invPosition)

            // Python filters [BOS]/[EOS]/[PAD] — Vocabulary uses BOS/EOS/PAD without brackets.
            guard let rhythm = rhythmTok else {
                // Control-like / unknown — skip append but still advance streams like greedy path
                outLift.append(liftSample)
                outPitch.append(pitchSample)
                outRhythm.append(rhythmSample)
                outArticulations.append(articulationSample)
                outSlurs.append(slurSample)
                continue
            }

            symbols.append(
                EncodedSymbol(
                    rhythm: rhythm,
                    pitch: pitchTok ?? EncodedSymbol.nonote,
                    lift: liftTok ?? EncodedSymbol.nonote,
                    articulation: articulationTok ?? EncodedSymbol.nonote,
                    slur: slurTok ?? EncodedSymbol.nonote,
                    position: positionTok ?? EncodedSymbol.nonote,
                    attentionPayload: stepOut.attentionBlob
                )
            )

            outLift.append(liftSample)
            outPitch.append(pitchSample)
            outRhythm.append(rhythmSample)
            outArticulations.append(articulationSample)
            outSlurs.append(slurSample)
        }

        return symbols
    }

    /// Mirrors `detokenize` in decoder_inference.py (skip BOS/EOS/PAD and bracketed forms).
    public static func detokenize(_ id: Int, _ inv: [Int: String]) -> String? {
        guard let t = inv[id] else { return nil }
        if t == "BOS" || t == "EOS" || t == "PAD" { return nil }
        if t == "[BOS]" || t == "[EOS]" || t == "[PAD]" { return nil }
        return t
    }
}

public struct DecoderStepInput: Sendable {
    public var stepIndex: Int
    public var rhythm: Int
    public var pitch: Int
    public var lift: Int
    public var articulation: Int
    public var slur: Int
    public var useFullContext: Bool
}

public struct DecoderStepOutput: Sendable {
    public var rhythmArgmax: Int
    public var pitchArgmax: Int
    public var liftArgmax: Int
    public var positionArgmax: Int
    public var articulationArgmax: Int
    public var slurArgmax: Int
    public var attentionBlob: Data?

    public init(
        rhythmArgmax: Int,
        pitchArgmax: Int,
        liftArgmax: Int,
        positionArgmax: Int,
        articulationArgmax: Int,
        slurArgmax: Int,
        attentionBlob: Data? = nil
    ) {
        self.rhythmArgmax = rhythmArgmax
        self.pitchArgmax = pitchArgmax
        self.liftArgmax = liftArgmax
        self.positionArgmax = positionArgmax
        self.articulationArgmax = articulationArgmax
        self.slurArgmax = slurArgmax
        self.attentionBlob = attentionBlob
    }
}

public protocol DecoderStepRunning: Sendable {
    func runStep(_ input: DecoderStepInput) throws -> DecoderStepOutput
}

/// Scaffold runner: refuses to invent logits. Replace with ORT CPU binding.
public struct UnconfiguredDecoderStepRunner: DecoderStepRunning {
    public init() {}
    public func runStep(_ input: DecoderStepInput) throws -> DecoderStepOutput {
        throw OMRError.sessionNotConfigured(
            "Decoder ORT CPU step not bound (step \(input.stepIndex)); refusing to fake logits"
        )
    }
}
