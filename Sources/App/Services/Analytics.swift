import Foundation
import UIKit

/// In-house funnel telemetry → POST https://photo.grepawk.com/api/telemetry.
/// Soft no-op on network errors. Never send photos, base64, email, or GPS.
@MainActor
final class Analytics {
    static let shared = Analytics()

    private let anonKey = "telemetry.anonId"
    private let sessionKey = "telemetry.sessionId"
    private let sessionTsKey = "telemetry.sessionTs"
    private let sessionTTL: TimeInterval = 30 * 60
    private let endpoint = URL(string: "https://photo.grepawk.com/api/telemetry")!
    private let appName = "omr-sheet-cam"

    private var didBoot = false

    var anonId: String {
        let existing = UserDefaults.standard.string(forKey: anonKey)
        if let existing, existing.count >= 8 { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: anonKey)
        return id
    }

    var sessionId: String {
        let now = Date().timeIntervalSince1970
        let prev = UserDefaults.standard.double(forKey: sessionTsKey)
        var sid = UserDefaults.standard.string(forKey: sessionKey)
        if sid == nil || prev == 0 || now - prev > sessionTTL {
            sid = UUID().uuidString
            UserDefaults.standard.set(sid, forKey: sessionKey)
        }
        UserDefaults.standard.set(now, forKey: sessionTsKey)
        return sid ?? UUID().uuidString
    }

    func bootstrap() {
        guard !didBoot else { return }
        didBoot = true
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        track("session_start")
        track("app_open", props: [
            "platform": "ios",
            "app_version": version ?? "unknown",
        ])
    }

    /// Whole words that mark a prop key as PII / bulky payload. Matched against the key's *words*
    /// (split on `_ - .` and camelCase), never as substrings: `platform`, `latency_ms`, `template`
    /// survive (P10.3: "lat" used to match inside "platform"); `user_email`, `gpsLat`, `lat` don't.
    nonisolated static let blockedKeyWords: Set<String> = [
        "email", "phone", "image", "photo", "base64", "gps", "lat", "lng", "latitude", "longitude", "token", "password",
    ]

    nonisolated static func keyWords(_ key: String) -> [String] {
        var words: [String] = [], cur = ""
        var prevLower = false
        for ch in key {
            if !(ch.isLetter || ch.isNumber) {
                if !cur.isEmpty { words.append(cur.lowercased()); cur = "" }
                prevLower = false
                continue
            }
            if ch.isUppercase, prevLower, !cur.isEmpty { words.append(cur.lowercased()); cur = "" }
            cur.append(ch)
            prevLower = ch.isLowercase || ch.isNumber
        }
        if !cur.isEmpty { words.append(cur.lowercased()) }
        return words
    }

    /// Drops PII-looking keys, inline images and oversized values; caps values at 200 chars.
    nonisolated static func clean(props: [String: String]) -> [String: String] {
        var cleaned: [String: String] = [:]
        for (k, v) in props {
            if keyWords(k).contains(where: blockedKeyWords.contains) { continue }
            if v.hasPrefix("data:image") || v.count > 200 { continue }
            cleaned[k] = String(v.prefix(200))
        }
        return cleaned
    }

    func track(_ event: String, props: [String: String] = [:]) {
        let cleaned = Self.clean(props: props)
        let payload: [String: Any] = [
            "app": appName,
            "event": event,
            "anon_id": anonId,
            "session_id": sessionId,
            "platform": "ios",
            "props": cleaned,
        ]
        Task {
            do {
                var req = URLRequest(url: endpoint)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: payload)
                req.timeoutInterval = 10
                let (_, resp) = try await URLSession.shared.data(for: req)
                #if DEBUG
                if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                    print("[Analytics] server error \(http.statusCode) for \(event)")
                }
                #endif
            } catch {
                #if DEBUG
                print("[Analytics] soft fail \(event): \(error.localizedDescription)")
                #endif
            }
        }
    }
}
