import Foundation

/// Token-string → SMF helpers for staff C-scale / metrical writeout.
///
/// Only interprets symbols already present in the upstream tokenizer /
/// `Vocabulary()` (e.g. rhythm `note_4`, pitch `C4`, lift `#`). Does **not**
/// invent token names or IDs.
public enum SymbolMIDIMapping: Sendable {

    /// Scientific pitch token (`C4`, `A#` is NOT used — accidentals live in `lift`) → MIDI note.
    /// Pitch tokens in vocab are natural letter+octave only (`C4`, `D4`, …).
    public static func midiNote(pitchToken: String, liftToken: String = EncodedSymbol.empty) -> UInt8? {
        guard pitchToken != EncodedSymbol.nonote, pitchToken != EncodedSymbol.empty else {
            return nil
        }
        // Expect Letter + optional digit octave, e.g. C4, B9
        guard let first = pitchToken.first else { return nil }
        let letter = String(first).uppercased()
        let octavePart = pitchToken.dropFirst()
        guard let octave = Int(octavePart) else { return nil }

        let base: Int
        switch letter {
        case "C": base = 0
        case "D": base = 2
        case "E": base = 4
        case "F": base = 5
        case "G": base = 7
        case "A": base = 9
        case "B": base = 11
        default: return nil
        }

        var semitone = (octave + 1) * 12 + base
        switch liftToken {
        case "#": semitone += 1
        case "##": semitone += 2
        case "b": semitone -= 1
        case "bb": semitone -= 2
        case "N", EncodedSymbol.empty, EncodedSymbol.nonote:
            break
        default:
            break
        }
        guard semitone >= 0, semitone <= 127 else { return nil }
        return UInt8(semitone)
    }

    /// Humdrum **kern duration from a `note_*` / `rest_*` rhythm token → ticks at `tpq`.
    ///
    /// Mirrors `kern_to_symbol_duration` + `SymbolDuration.fraction` (relative to whole note),
    /// then `ticks = fraction * 4 * tpq` (whole note = 4 quarters).
    public static func durationTicks(
        rhythmToken: String,
        tpq: Int = Int(SMFWriter.ticksPerQuarter)
    ) -> Int? {
        guard let kern = kernSuffix(fromRhythm: rhythmToken) else { return nil }
        guard let whole = wholeNoteFraction(kern: kern) else { return nil }
        // whole-note fraction * 4 quarters * tpq
        let ticks = whole * 4.0 * Double(tpq)
        return max(0, Int(ticks.rounded()))
    }

    /// Extract kern suffix after `note_` / `rest_`.
    public static func kernSuffix(fromRhythm rhythm: String) -> String? {
        if rhythm.hasPrefix("note_") {
            return String(rhythm.dropFirst(5))
        }
        if rhythm.hasPrefix("rest_") {
            return String(rhythm.dropFirst(5))
        }
        return nil
    }

    public static func isNoteRhythm(_ rhythm: String) -> Bool {
        rhythm.hasPrefix("note_")
    }

    public static func isRestRhythm(_ rhythm: String) -> Bool {
        rhythm.hasPrefix("rest_")
    }

    /// Build sequential note events from decoded symbols (skips non-notes; advances time on rests).
    /// Chord tokens are ignored for Gate-1 monophonic C-scale; no invented pitches.
    public static func noteEvents(
        from symbols: [EncodedSymbol],
        tpq: Int = Int(SMFWriter.ticksPerQuarter)
    ) -> [SMFWriter.NoteEvent] {
        var onset = 0
        var events: [SMFWriter.NoteEvent] = []
        for sym in symbols {
            if isRestRhythm(sym.rhythm) {
                let dur = durationTicks(rhythmToken: sym.rhythm, tpq: tpq) ?? tpq
                onset += dur
                continue
            }
            guard isNoteRhythm(sym.rhythm) else { continue }
            guard let midi = midiNote(pitchToken: sym.pitch, liftToken: sym.lift) else {
                continue
            }
            let dur = durationTicks(rhythmToken: sym.rhythm, tpq: tpq) ?? tpq
            // Grace (kern contains G) → zero-duration in upstream; skip sounding note.
            if let kern = kernSuffix(fromRhythm: sym.rhythm), kern.contains("G") {
                continue
            }
            events.append(
                SMFWriter.NoteEvent(midiNote: midi, onsetTicks: onset, durationTicks: max(1, dur))
            )
            onset += dur
        }
        return events
    }

    // MARK: - Kern (upstream-faithful)

    /// Returns duration as a fraction of a whole note (`1.0` = whole).
    static func wholeNoteFraction(kern: String) -> Double? {
        if kern.hasSuffix("m") {
            // Multirest — upstream returns Fraction(1) (one whole)
            return 1.0
        }
        if kern.contains("G") {
            return 0.0
        }

        var i = kern.startIndex
        while i < kern.endIndex, kern[i].isNumber {
            i = kern.index(after: i)
        }
        let baseStr = String(kern[..<i])
        let rest = String(kern[i...])
        let base = Int(baseStr) ?? 4
        let dots = rest.filter { $0 == "." }.count

        if base == 0 {
            // Whole-measure rest convention in upstream
            return dotted(1.0, dots: dots)
        }

        let baseDuration: Double
        let actualNotes: Double
        let normalNotes: Double
        if base > 0, (base & (base - 1)) == 0 {
            // Power of two
            baseDuration = 1.0 / Double(base)
            actualNotes = 1
            normalNotes = 1
        } else {
            // Tuplet: next lower power of two
            let normal = priorPowerOfTwo(base)
            baseDuration = 1.0 / Double(normal)
            actualNotes = Double(base)
            normalNotes = Double(normal)
        }

        var dur = dotted(baseDuration, dots: dots)
        if actualNotes != normalNotes {
            dur *= normalNotes / actualNotes
        }
        return dur
    }

    private static func dotted(_ base: Double, dots: Int) -> Double {
        var dur = base
        var add = base / 2.0
        for _ in 0..<dots {
            dur += add
            add /= 2.0
        }
        return dur
    }

    private static func priorPowerOfTwo(_ n: Int) -> Int {
        // Mirror upstream vocabulary.prior_power_of_two: largest power of two <= n.
        if n < 1 { return 1 }
        return 1 << (Int.bitWidth - 1 - n.leadingZeroBitCount)
    }
}
