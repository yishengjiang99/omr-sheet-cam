import Foundation

/// One sounding note recovered from Standard MIDI File bytes.
///
/// Player-side view only: `track` is the SMF `MTrk` chunk index (0 = conductor), not an
/// OMR staff index. This type knows nothing about tokens / symbols / OMR logic.
struct MIDINote: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// Absolute onset in SMF ticks (metrical division, e.g. 480 TPQ).
    var tick: Int
    /// MIDI note number 0...127.
    var pitch: Int
    /// Note-off tick minus note-on tick.
    var duration: Int
    /// Zero-based `MTrk` chunk index the note lives in.
    var track: Int
    /// MIDI channel 0...15.
    var channel: Int
    /// Note-on velocity (always > 0 — velocity-0 note-ons are treated as note-offs).
    var velocity: Int

    var description: String { "(t\(tick) p\(pitch) d\(duration) trk\(track))" }
}

/// Minimal SMF (format 0/1) note on/off parser for playback + highlight smoke.
///
/// Consumes only MIDI bytes (e.g. `ParseSheetMusicResult.midi` or `SMFWriter` output);
/// it is intentionally independent of the OMR package so the player / highlighter can
/// use it as a "midi-fallback" note source.
///
/// Handles: running status, note-on velocity 0 as note-off, meta + sysex skipping,
/// unknown chunk skipping, overlapping same-pitch notes (FIFO pairing), and notes left
/// hanging at end of track (closed at the track's final tick).
enum MIDINoteExtractor {

    struct Header: Equatable, Sendable {
        var format: Int
        var trackCount: Int
        var division: Int
    }

    enum ExtractError: Error, Equatable {
        case notSMF
        case smpteDivisionUnsupported
        case truncated(offset: Int)
        case unexpectedDataByte(offset: Int)
    }

    /// Sounding notes sorted by `(tick, track, pitch, channel)`.
    static func notes(from data: Data) throws -> [MIDINote] {
        try extract(from: data).notes
    }

    /// Count of note-on events with velocity > 0 (the "sounding note" count).
    static func soundingNoteCount(in data: Data) throws -> Int {
        try notes(from: data).count
    }

    static func extract(from data: Data) throws -> (header: Header, notes: [MIDINote]) {
        let bytes = [UInt8](data)
        guard bytes.count >= 14,
              bytes[0] == 0x4D, bytes[1] == 0x54, bytes[2] == 0x68, bytes[3] == 0x64 // "MThd"
        else { throw ExtractError.notSMF }

        let headerLength = Int(try readU32(bytes, 4))
        guard headerLength >= 6 else { throw ExtractError.notSMF }
        let format = Int(try readU16(bytes, 8))
        let trackCount = Int(try readU16(bytes, 10))
        let division = Int(try readU16(bytes, 12))
        guard division & 0x8000 == 0 else { throw ExtractError.smpteDivisionUnsupported }
        let header = Header(format: format, trackCount: trackCount, division: division)

        var notes: [MIDINote] = []
        var offset = 8 + headerLength
        var trackIndex = 0
        while offset + 8 <= bytes.count {
            let isTrack = bytes[offset] == 0x4D && bytes[offset + 1] == 0x54
                && bytes[offset + 2] == 0x72 && bytes[offset + 3] == 0x6B // "MTrk"
            let length = Int(try readU32(bytes, offset + 4))
            let bodyStart = offset + 8
            let bodyEnd = bodyStart + length
            guard bodyEnd <= bytes.count else { throw ExtractError.truncated(offset: offset) }
            if isTrack {
                notes.append(contentsOf: try parseTrack(bytes, start: bodyStart, end: bodyEnd, track: trackIndex))
                trackIndex += 1
            }
            // Non-MTrk chunks are skipped per the SMF spec.
            offset = bodyEnd
        }

        notes.sort { a, b in
            if a.tick != b.tick { return a.tick < b.tick }
            if a.track != b.track { return a.track < b.track }
            if a.pitch != b.pitch { return a.pitch < b.pitch }
            return a.channel < b.channel
        }
        return (header, notes)
    }

    // MARK: - Track parsing

    private struct PendingOn {
        var tick: Int
        var velocity: Int
    }

    private static func parseTrack(_ bytes: [UInt8], start: Int, end: Int, track: Int) throws -> [MIDINote] {
        var out: [MIDINote] = []
        // key = channel * 128 + pitch → FIFO of open note-ons
        var pending: [Int: [PendingOn]] = [:]
        var i = start
        var tick = 0
        var runningStatus: UInt8?

        func close(channel: Int, pitch: Int, at t: Int) {
            let key = channel * 128 + pitch
            guard var queue = pending[key], !queue.isEmpty else { return } // stray note-off
            let on = queue.removeFirst()
            pending[key] = queue.isEmpty ? nil : queue
            out.append(MIDINote(
                tick: on.tick,
                pitch: pitch,
                duration: max(0, t - on.tick),
                track: track,
                channel: channel,
                velocity: on.velocity
            ))
        }

        while i < end {
            let (delta, afterDelta) = try readVLQ(bytes, i, end: end)
            tick += delta
            i = afterDelta
            guard i < end else { throw ExtractError.truncated(offset: i) }

            var status = bytes[i]
            if status & 0x80 != 0 {
                i += 1
            } else {
                // Running status: reuse previous channel status; `i` stays on the data byte.
                guard let rs = runningStatus else { throw ExtractError.unexpectedDataByte(offset: i) }
                status = rs
            }

            switch status {
            case 0xFF: // meta: type, VLQ length, data
                runningStatus = nil
                guard i < end else { throw ExtractError.truncated(offset: i) }
                let type = bytes[i]
                i += 1
                let (len, afterLen) = try readVLQ(bytes, i, end: end)
                i = afterLen + len
                guard i <= end else { throw ExtractError.truncated(offset: afterLen) }
                if type == 0x2F { // end of track
                    i = end
                }
            case 0xF0, 0xF7: // sysex / escape: VLQ length, data
                runningStatus = nil
                let (len, afterLen) = try readVLQ(bytes, i, end: end)
                i = afterLen + len
                guard i <= end else { throw ExtractError.truncated(offset: afterLen) }
            default:
                guard status >= 0x80, status < 0xF0 else {
                    // System common / realtime bytes are not valid in SMF tracks; bail safely.
                    throw ExtractError.unexpectedDataByte(offset: i)
                }
                runningStatus = status
                let kind = status & 0xF0
                let channel = Int(status & 0x0F)
                let dataCount = (kind == 0xC0 || kind == 0xD0) ? 1 : 2
                guard i + dataCount <= end else { throw ExtractError.truncated(offset: i) }
                let d1 = Int(bytes[i] & 0x7F)
                let d2 = dataCount == 2 ? Int(bytes[i + 1] & 0x7F) : 0
                i += dataCount

                if kind == 0x90, d2 > 0 {
                    pending[channel * 128 + d1, default: []].append(PendingOn(tick: tick, velocity: d2))
                } else if kind == 0x80 || (kind == 0x90 && d2 == 0) {
                    close(channel: channel, pitch: d1, at: tick)
                }
            }
        }

        // Notes never switched off: close at the final track tick so they still count as sounding.
        for key in pending.keys.sorted() {
            while pending[key]?.isEmpty == false {
                close(channel: key / 128, pitch: key % 128, at: tick)
            }
        }
        return out
    }

    // MARK: - Binary helpers

    private static func readVLQ(_ bytes: [UInt8], _ start: Int, end: Int) throws -> (value: Int, next: Int) {
        var value = 0
        var i = start
        for _ in 0..<4 {
            guard i < end else { throw ExtractError.truncated(offset: i) }
            let b = bytes[i]
            i += 1
            value = (value << 7) | Int(b & 0x7F)
            if b & 0x80 == 0 { return (value, i) }
        }
        throw ExtractError.truncated(offset: start) // VLQ longer than 4 bytes is invalid
    }

    private static func readU16(_ bytes: [UInt8], _ at: Int) throws -> UInt16 {
        guard at + 2 <= bytes.count else { throw ExtractError.truncated(offset: at) }
        return UInt16(bytes[at]) << 8 | UInt16(bytes[at + 1])
    }

    private static func readU32(_ bytes: [UInt8], _ at: Int) throws -> UInt32 {
        guard at + 4 <= bytes.count else { throw ExtractError.truncated(offset: at) }
        return UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16
            | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
    }
}
