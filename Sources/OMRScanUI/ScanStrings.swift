import Foundation

/// Copy for the scan UI. The package ships English defaults (`Resources/en.lproj/OMRScan.strings`);
/// a host overrides any key by providing the same key in an `OMRScan` strings table in its own
/// bundle (`hostBundle`, `Bundle.main` by default). Missing keys fall back to the package default.
public enum ScanStrings {
    /// Where host overrides are looked up (tests point this at a fixture bundle).
    public static var hostBundle: Bundle = .main

    public static func string(_ key: String, _ fallback: String) -> String {
        let host = hostBundle.localizedString(forKey: key, value: nil, table: "OMRScan")
        if host != key { return host }
        return Bundle.module.localizedString(forKey: key, value: fallback, table: "OMRScan")
    }

    public static func format(_ key: String, _ fallback: String, _ args: CVarArg...) -> String {
        String(format: string(key, fallback), arguments: args)
    }
}
