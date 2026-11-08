import Foundation

enum InstallOrigin {
    static let caskroomURLs = [
        URL(fileURLWithPath: "/opt/homebrew/Caskroom"),
        URL(fileURLWithPath: "/usr/local/Caskroom"),
    ]

    /// The `sharingan` Homebrew cask installs upstream CodexBar, which ships under this bundle identifier.
    static let upstreamCaskBundleIdentifier = "com.steipete.codexbar"

    /// Sharingan: Homebrew updates run `brew upgrade --cask sharingan`, which would replace this fork with
    /// upstream CodexBar. Only the upstream bundle may ever be treated as managed by that cask.
    static func isUpstreamHomebrewCask(
        appBundleURL: URL,
        bundleIdentifier: String?,
        caskroomURLs: [URL] = Self.caskroomURLs) -> Bool
    {
        guard bundleIdentifier == self.upstreamCaskBundleIdentifier else { return false }
        return self.isHomebrewCask(appBundleURL: appBundleURL, caskroomURLs: caskroomURLs)
    }

    static func isHomebrewCask(
        appBundleURL: URL,
        caskroomURLs: [URL] = Self.caskroomURLs) -> Bool
    {
        !self.homebrewPrefixes(appBundleURL: appBundleURL, caskroomURLs: caskroomURLs).isEmpty
    }

    static func homebrewPrefix(
        appBundleURL: URL,
        caskroomURLs: [URL] = Self.caskroomURLs) -> URL?
    {
        let prefixes = self.homebrewPrefixes(appBundleURL: appBundleURL, caskroomURLs: caskroomURLs)
        return prefixes.count == 1 ? prefixes[0] : nil
    }

    private static func homebrewPrefixes(appBundleURL: URL, caskroomURLs: [URL]) -> [URL] {
        let resolved = appBundleURL.resolvingSymlinksInPath().standardizedFileURL
        var prefixes: [URL] = []
        let legacyCask = resolved.deletingLastPathComponent().deletingLastPathComponent()
        if resolved.lastPathComponent == "Sharingan.app", legacyCask.lastPathComponent == "sharingan",
           legacyCask.deletingLastPathComponent().lastPathComponent == "Caskroom"
        {
            prefixes.append(legacyCask.deletingLastPathComponent().deletingLastPathComponent())
        }

        let fileManager = FileManager.default
        guard (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return prefixes
        }

        // Cask app artifacts are moved into the app directory. Homebrew leaves a symlink
        // in Caskroom pointing to the installed app, rather than the other way around.
        let linkedPrefixes = caskroomURLs.filter { caskroom in
            let caskURL = caskroom.appendingPathComponent("sharingan", isDirectory: true)
            guard let versions = try? fileManager.contentsOfDirectory(
                at: caskURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]) else { return false }

            return versions.contains { version in
                let artifact = version.appendingPathComponent("Sharingan.app")
                return (try? fileManager.destinationOfSymbolicLink(atPath: artifact.path)) != nil &&
                    artifact.resolvingSymlinksInPath().standardizedFileURL == resolved
            }
        }.map { $0.deletingLastPathComponent() }
        return Array(Set((prefixes + linkedPrefixes).map { $0.resolvingSymlinksInPath().standardizedFileURL }))
    }
}
