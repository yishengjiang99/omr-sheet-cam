import Foundation

/// Mirrors `homr.transformer.vocabulary.EncodedSymbol` (decode branches only).
public struct EncodedSymbol: Equatable, Sendable, CustomStringConvertible {
    public var rhythm: String
    public var pitch: String
    public var lift: String
    public var articulation: String
    public var slur: String
    public var position: String
    /// Attention-derived coordinates; imprecise. Shape deferred until ORT binding lands.
    public var attentionPayload: Data?

    public init(
        rhythm: String,
        pitch: String = EncodedSymbol.nonote,
        lift: String = EncodedSymbol.nonote,
        articulation: String = EncodedSymbol.nonote,
        slur: String = EncodedSymbol.nonote,
        position: String = EncodedSymbol.nonote,
        attentionPayload: Data? = nil
    ) {
        self.rhythm = rhythm
        self.pitch = pitch
        self.lift = lift
        self.articulation = articulation
        self.slur = slur
        self.position = position
        self.attentionPayload = attentionPayload
    }

    /// Upstream `nonote = "."`
    public static let nonote = "."
    /// Upstream `empty = "_"`
    public static let empty = "_"

    public var isControlSymbol: Bool {
        rhythm == "BOS" || rhythm == "EOS" || rhythm == "PAD"
    }

    public var description: String {
        [rhythm, pitch, lift, articulation, slur, position].joined(separator: " ")
    }
}
