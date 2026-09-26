import SwiftUI

/// Third-party notices shown in the app (Settings → Source code & license → Acknowledgements).
enum Acknowledgements {
    /// GeneralUser GS 2.0.2 by S. Christian Collins, bundled as `models/GeneralUser-GS.sf2`
    /// (pinned in models.lock). Text copied verbatim from the bank's own INFO/ICMT chunk; same
    /// "License v2.0" as https://github.com/mrbumpy409/GeneralUser-GS (documentation/LICENSE.txt).
    static let generalUserGS = """
    GeneralUser GS 2.0.2
    Copyright 1997-2025 by S. Christian Collins
    https://www.schristiancollins.com

    ***     License v2.0    ***

    ** License of the complete work **
    You may use GeneralUser GS without restriction for your own music creation, private or commercial. This SoundFont bank is provided to the community free of charge. Please feel free to use it in your software projects, and to modify the SoundFont bank or its packaging to suit your needs.

    ** License of contained samples **
    GeneralUser GS inherits the usage rights of the samples contained within, all of which allow full use in music production, including the ability to make profit from musical recordings created with GeneralUser GS.

    Many of the samples are original, but some were taken from other banks freely (and legally) available on the Internet from various SoundFont websites. Because GeneralUser GS originated as a personal project with no intention for publication, I cannot be 100% sure where all of the samples originated, although I do know that none of them came from commercially published SoundFont packages or sample CDs. Regardless, many "free" SoundFonts available on the web may indeed contain samples of questionable origin. My understanding of the copyrights of all samples is only as good as the information provided by the original sources. If you become aware of any restricted samples being used in GeneralUser GS, please let me know so I can replace them.

    This uncertainty may concern you if you intend to use GeneralUser GS in a commercial software product. That being said, I have never received any complaint regarding sample ownership since I published the original GeneralUser GS back in 2000, and as far as I am aware, neither have any of the companies creating commercial software products using GeneralUser GS.

    ** More info **
    If you plan to feature GeneralUser GS on your own website, please do not link directly to my download files. Either link to my website, or provide your own local copy instead.

    I hope you enjoy GeneralUser GS! This SoundFont bank is the product of many years of hard work.

    You can find updates to GeneralUser GS and more of my virtual instruments at: http://www.schristiancollins.com

    I can be reached via the contact page on my website here: https://www.schristiancollins.com/contact

    Thank you!
    -~Chris
    """

    struct Entry: Identifiable {
        var title: String
        var text: String
        var id: String { title }
    }

    static let entries: [Entry] = [
        Entry(title: "GeneralUser GS SoundFont", text: generalUserGS),
    ]
}

/// One NOTICE entry ("1. homr …", "Appendix A: …") or a bundled third-party notice file.
struct NoticeEntry: Identifiable, Hashable {
    var title: String
    var text: String
    var id: String { title }
}

enum NoticeParser {
    /// Splits the repo NOTICE into its preamble, numbered third-party entries and appendices.
    static func entries(_ notice: String) -> [NoticeEntry] {
        var out: [NoticeEntry] = []
        var title = "About this app"
        var body: [Substring] = []
        func flush() {
            let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { out.append(NoticeEntry(title: title, text: text)) }
            body = []
        }
        for line in notice.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("=====") { continue }
            let isNumbered = line.first?.isNumber == true && line.range(of: #"^\d+\. "#, options: .regularExpression) != nil
            let isAppendix = line.hasPrefix("Appendix ")
            if isNumbered || isAppendix {
                flush()
                title = String(line).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.trimmingCharacters(in: .whitespaces) == "Third-party components" { continue }
            body.append(line)
        }
        flush()
        return out
    }
}

/// Settings → Source code & license → Acknowledgements: every NOTICE entry, the GeneralUser GS
/// license, and ONNX Runtime's license + ThirdPartyNotices (v1.24.2, the version the app links).
struct AcknowledgementsView: View {
    private let notice = NoticeParser.entries(LicenseTexts.notice())

    var body: some View {
        List {
            Section("NOTICE") {
                ForEach(notice) { e in
                    NavigationLink(e.title) { LicenseTextScreen(title: e.title, text: e.text) }
                }
            }
            Section("Bundled components") {
                ForEach(Acknowledgements.entries) { entry in
                    NavigationLink(entry.title) { LicenseTextScreen(title: entry.title, text: entry.text) }
                }
                NavigationLink("ONNX Runtime (MIT)") {
                    LicenseTextScreen(title: "ONNX Runtime", text: LicenseTexts.resource("ONNXRuntime-LICENSE"))
                }
                NavigationLink("ONNX Runtime third-party notices") {
                    LicenseTextScreen(title: "ONNX Runtime notices", text: LicenseTexts.resource("ONNXRuntime-ThirdPartyNotices"))
                }
                .accessibilityIdentifier("ack.ortNotices")
            }
        }
        .navigationTitle("Acknowledgements")
    }
}
