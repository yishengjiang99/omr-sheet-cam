import Foundation
import SF2Player

/// F10.3: maps thrown errors to short plain-language text for the UI. Raw `\(error)` (enum case
/// names, NSError dumps, file paths) stays in `DiagnosticsLog` / the Details disclosure.
enum UserFacingError {
    /// What the user was doing; picks the lead sentence.
    enum Action {
        case play, saveCapture, saveToLibrary, delete, rename, sample, capture

        var lead: String {
            switch self {
            case .play: return "Can't play this."
            case .saveCapture: return "Couldn't save the photo."
            case .saveToLibrary: return "Couldn't save to your Library."
            case .delete: return "Couldn't delete this scan."
            case .rename: return "Couldn't rename this scan."
            case .sample: return "The sample isn't available."
            case .capture: return "Couldn't take the photo."
            }
        }

        var fallbackHint: String {
            switch self {
            case .play: return "Try again, or open another scan."
            case .saveCapture, .saveToLibrary, .delete, .rename: return "Please try again."
            case .sample: return "Try again, or take a photo instead."
            case .capture: return "Please try again."
            }
        }
    }

    /// "<lead> <reason>" when the cause is known, else "<lead> <hint>".
    static func message(for error: Error, action: Action) -> String {
        "\(action.lead) \(reason(for: error) ?? action.fallbackHint)"
    }

    /// Plain-language cause for errors we know; nil for anything else (never the raw text).
    static func reason(for error: Error) -> String? {
        switch error {
        case let e as PlaylistStore.StoreError:
            switch e {
            case .notDeletable: return "Bundled samples can't be changed."
            case .notFound: return "This scan is no longer in your Library."
            case .invalidMIDI: return "The music file couldn't be read."
            }
        case is BundledSoundFont.LoadError:
            return "The piano sounds are missing. Reinstalling the app should fix this."
        case let e as SF2MIDIPlayer.PlayerError:
            switch e {
            case .soundFontNotLoaded: return "The piano sounds haven't loaded yet. Try again in a moment."
            case .noSequence: return "There is no music to play."
            case .audio: return "The audio output isn't available. Check that nothing else is using it."
            }
        case is SampleMIDI.SampleError, is SamplePicture.LoadError:
            return "The sample file is missing from this build."
        case is CaptureStore.SaveError:
            return "The photo couldn't be encoded."
        case is DecodingError:
            return "The saved data couldn't be read."
        default:
            break
        }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return "The file is missing. It may have been deleted."
            case NSFileWriteOutOfSpaceError:
                return "Your device is out of storage space."
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                return "The app isn't allowed to use that file."
            case NSFileReadCorruptFileError:
                return "The file is damaged."
            default: break
            }
        }
        return nil
    }
}
