import SharinganCore
import Testing
@testable import Sharingan

@MainActor
struct ProviderBrowsingSearchTests {
    @Test
    func `provider search recognizes existing CLI aliases`() {
        #expect(ProvidersPane.filteredProviders(
            [.codex, .alibaba],
            query: "  BAILÍAN  ",
            displayName: { ProviderDescriptorRegistry.descriptor(for: $0).metadata.displayName }) == [.alibaba])
    }

    @Test
    func `provider search matches every word across names and CLI aliases`() {
        let displayName: (UsageProvider) -> String = {
            ProviderDescriptorRegistry.descriptor(for: $0).metadata.displayName
        }
        #expect(ProvidersPane.filteredProviders(
            [.codex, .alibaba], query: "Alibaba BAILÍAN", displayName: displayName) == [.alibaba])
        #expect(ProvidersPane.filteredProviders(
            [.codex, .alibaba], query: "Alibaba missing", displayName: displayName).isEmpty)
        #expect(ProvidersPane.filteredProviders(
            [.codex, .alibaba], query: "  ", displayName: displayName) == [.codex, .alibaba])
    }
}
