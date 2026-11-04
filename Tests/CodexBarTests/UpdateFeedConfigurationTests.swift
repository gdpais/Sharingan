import Foundation
import Testing
@testable import CodexBar

@MainActor
struct UpdateFeedConfigurationTests {
    @Test(arguments: [
        nil,
        "",
        "   ",
        "not a url",
        "http://example.invalid/appcast.xml",
        "https://",
    ])
    func `missing or unusable feed URLs disable Sparkle`(feed: String?) {
        var info: [String: Any] = ["CFBundleIdentifier": "com.gdpais.sharingan"]
        if let feed {
            info["SUFeedURL"] = feed
        }

        #expect(!UpdateFeedConfiguration.hasFeed(infoDictionary: info))
    }

    @Test
    func `missing Info plist disables Sparkle`() {
        #expect(!UpdateFeedConfiguration.hasFeed(infoDictionary: nil))
    }

    @Test
    func `an https appcast enables Sparkle`() {
        let info: [String: Any] = ["SUFeedURL": "https://example.invalid/appcast.xml"]

        #expect(UpdateFeedConfiguration.hasFeed(infoDictionary: info))
    }

    @Test
    func `a build without a feed offers no update check in the menu`() {
        let updater = DisabledUpdaterController(unavailableReason: "Updates unavailable in this build.")
        let section = MenuDescriptor.metaSection(updateReady: false, canCheckForUpdates: updater.isAvailable)
        let actions = section.entries.compactMap { entry -> MenuDescriptor.MenuAction? in
            guard case let .action(_, action) = entry else { return nil }
            return action
        }

        #expect(!updater.isAvailable)
        #expect(!actions.contains(.checkForUpdates))
        #expect(!actions.contains(.installUpdate))
    }
}
