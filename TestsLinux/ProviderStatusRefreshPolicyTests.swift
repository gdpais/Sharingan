import Foundation
@testable import SharinganCore
import Testing

struct ProviderStatusRefreshPolicyTests {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    @Test
    func `a provider without a published status is always due`() {
        #expect(ProviderStatusRefreshPolicy.isDue(lastSuccessAt: nil, indicator: nil, now: self.start))
        #expect(ProviderStatusRefreshPolicy.isDue(lastSuccessAt: self.start, indicator: nil, now: self.start))
        #expect(ProviderStatusRefreshPolicy.isDue(lastSuccessAt: nil, indicator: .none, now: self.start))
    }

    @Test
    func `a healthy provider is polled every fifteen minutes`() {
        let justBefore = self.start.addingTimeInterval(15 * 60 - 1)
        let atInterval = self.start.addingTimeInterval(15 * 60)
        #expect(!ProviderStatusRefreshPolicy.isDue(lastSuccessAt: self.start, indicator: .none, now: justBefore))
        #expect(ProviderStatusRefreshPolicy.isDue(lastSuccessAt: self.start, indicator: .none, now: atInterval))
    }

    @Test(arguments: [ProviderStatusIndicator.minor, .major, .critical, .maintenance, .unknown])
    func `a provider with an open issue keeps the short interval`(indicator: ProviderStatusIndicator) {
        let justBefore = self.start.addingTimeInterval(2 * 60 - 1)
        let atInterval = self.start.addingTimeInterval(2 * 60)
        #expect(!ProviderStatusRefreshPolicy.isDue(lastSuccessAt: self.start, indicator: indicator, now: justBefore))
        #expect(ProviderStatusRefreshPolicy.isDue(lastSuccessAt: self.start, indicator: indicator, now: atInterval))
    }
}
