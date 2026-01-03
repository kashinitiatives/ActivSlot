import Foundation

extension Bundle {
    /// Returns the app version string (e.g., "1.0.0")
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Returns the build number string (e.g., "1")
    var buildNumber: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// Returns the full version string (e.g., "1.0.0 (1)")
    var fullVersion: String {
        return "\(appVersion) (\(buildNumber))"
    }

    /// Returns the app name
    var appName: String {
        return infoDictionary?["CFBundleName"] as? String ?? "Activslot"
    }
}
