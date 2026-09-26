import Foundation

/// Minimal Standard MIDI File writer — **Format 1**, **480 TPQ**, metrical division.
///
/// Web-player-compatible subset: tempo track + one note track.
/// Gate-1: usable for header/structure tests and later token→note mapping.
public struct SMFWriter: Sendable {
    public static let ticksPerQuarter: UInt16 = 480
    public static let format: UInt16 = 1

    public var tempoMicroseconds: UInt32
    public var defaultVelocity: UInt8

    public init(tempoMicroseconds: UInt32 = 500_000, defaultVelocity: UInt8 = 80) {
        self.tempoMicroseconds = tempoMicroseconds
        self.defaultVelocity = defaultVelocity
    }

    public struct NoteEvent: Equatable, Sendable {
        public var midiNote: UInt8
        public var onsetTicks: Int
        public var durationTicks: Int
        public var channel: UInt8
        public var velocity: UInt8?

        public init(
            midiNote: UInt8,
            onsetTicks: Int,
            durationTicks: Int,
            channel: UInt8 = 0,
            velocity: UInt8? = nil
        ) {
            self.midiNote = midiNote
            self.onsetTicks = onsetTicks
            self.durationTicks = durationTicks
            self.channel = channel
            self.velocity = velocity
        }
    }

    /// Write SMF format 1 with a tempo/conductor track and a note track.
    public func write(notes: [NoteEvent]) -> Data {
        var tracks: [Data] = []
        tracks.append(makeTempoTrack())
        tracks.append(makeNoteTrack(notes: notes))
        return assembleFile(tracks: tracks)
    }

    /// Empty score (tempo + empty note track) — useful for structure tests.
    public func writeEmpty() -> Data {
        write(notes: [])
    }

    // MARK: - File assembly

    private func assembleFile(tracks: [Data]) -> Data {
        var data = Data()
        data.append(ascii("MThd"))
        data.append(u32be(6)) // header body length
        data.append(u16be(Self.format))
        data.append(u16be(UInt16(tracks.count)))
        data.append(u16be(Self.ticksPerQuarter)) // metrical division (positive)
        for track in tracks {
            data.append(ascii("MTrk"))
            data.append(u32be(UInt32(track.count)))
            data.append(track)
        }
        return data
    }

    private func makeTempoTrack() -> Data {
        var events = Data()
        // delta 0, meta FF 51 03 tttttt
        events.append(contentsOf: encodeVLQ(0))
        events.append(contentsOf: [0xFF, 0x51, 0x03])
        events.append(u24be(tempoMicroseconds))
        // end of track
        events.append(contentsOf: encodeVLQ(0))
        events.append(contentsOf: [0xFF, 0x2F, 0x00])
        return events
    }

    private func makeNoteTrack(notes: [NoteEvent]) -> Data {
        struct MIDIInstant: Comparable {
            var tick: Int
            var order: Int // note-off before note-on at same tick
            var bytes: [UInt8]
            static func < (lhs: MIDIInstant, rhs: MIDIInstant) -> Bool {
                if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
                return lhs.order < rhs.order
            }
        }

        var instants: [MIDIInstant] = []
        for (i, n) in notes.enumerated() {
            let vel = n.velocity ?? defaultVelocity
            let ch = n.channel & 0x0F
            let on: [UInt8] = [0x90 | ch, n.midiNote, vel]
            let off: [UInt8] = [0x80 | ch, n.midiNote, 0x40]
            instants.append(MIDIInstant(tick: n.onsetTicks, order: 1 + i, bytes: on))
            instants.append(
                MIDIInstant(tick: n.onsetTicks + max(0, n.durationTicks), order: 0, bytes: off)
            )
        }
        instants.sort()

        var events = Data()
        var lastTick = 0
        for inst in instants {
            let delta = max(0, inst.tick - lastTick)
            events.append(contentsOf: encodeVLQ(delta))
            events.append(contentsOf: inst.bytes)
            lastTick = inst.tick
        }
        events.append(contentsOf: encodeVLQ(0))
        events.append(contentsOf: [0xFF, 0x2F, 0x00])
        return events
    }

    // MARK: - Binary helpers

    public static func encodeVLQ(_ value: Int) -> [UInt8] {
        var v = UInt32(max(0, value))
        var stack: [UInt8] = []
        stack.append(UInt8(v & 0x7F))
        v >>= 7
        while v > 0 {
            stack.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        return stack.reversed()
    }

    private func ascii(_ s: String) -> Data {
        Data(s.utf8)
    }

    private func u16be(_ v: UInt16) -> Data {
        Data([UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
    }

    private func u32be(_ v: UInt32) -> Data {
        Data([
            UInt8((v >> 24) & 0xFF),
            UInt8((v >> 16) & 0xFF),
            UInt8((v >> 8) & 0xFF),
            UInt8(v & 0xFF),
        ])
    }

    private func u24be(_ v: UInt32) -> Data {
        Data([
            UInt8((v >> 16) & 0xFF),
            UInt8((v >> 8) & 0xFF),
            UInt8(v & 0xFF),
        ])
    }
}

/// Lightweight SMF header inspection for tests (no full parser).
public enum SMFHeaderInspector {
    public struct Header: Equatable, Sendable {
        public var format: UInt16
        public var trackCount: UInt16
        public var division: UInt16
    }

    public static func readHeader(from data: Data) -> Header? {
        guard data.count >= 14 else { return nil }
        let magic = String(data: data[0..<4], encoding: .ascii)
        guard magic == "MThd" else { return nil }
        let format = u16(data, 8)
        let tracks = u16(data, 10)
        let division = u16(data, 12)
        // Metrical division: high bit clear
        guard division & 0x8000 == 0 else { return nil }
        return Header(format: format, trackCount: tracks, division: division)
    }

    public static func trackChunkCount(in data: Data) -> Int {
        var count = 0
        var i = 14
        let bytes = [UInt8](data)
        while i + 8 <= bytes.count {
            let tag = String(bytes: bytes[i..<i + 4], encoding: .ascii)
            let len = Int(u32(data, i + 4))
            guard tag == "MTrk" else { break }
            count += 1
            i += 8 + len
        }
        return count
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }
}
