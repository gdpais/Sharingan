import Testing
@testable import Sharingan

struct SharinganLaunchModeTests {
    @Test
    func `normal launch starts the application`() {
        #expect(SharinganLaunchMode.resolve(arguments: ["/Applications/Sharingan"]) == .application)
    }

    @Test
    func `hook event launch skips application initialization`() {
        #expect(SharinganLaunchMode.resolve(
            arguments: ["/Applications/Sharingan", "--hook-event"]) == .hookEvent)
    }

    @Test
    func `hook event is recognized among other arguments`() {
        #expect(SharinganLaunchMode.resolve(
            arguments: ["/Applications/Sharingan", "--verbose", "--hook-event"]) == .hookEvent)
    }

    @Test
    func `similar argument still starts the application`() {
        #expect(SharinganLaunchMode.resolve(
            arguments: ["/Applications/Sharingan", "--hook-events"]) == .application)
    }
}
