import Testing
@testable import SharinganCore

struct TestProcessSafetyTests {
    @Test
    func `current process is recognized without callers supplying runner signals`() {
        #expect(TestProcessSafety.isRunning)
    }

    @Test(arguments: [["/tmp/Suite.xctest"], ["swift-testing"], ["/tmp/XCTestRunner"]])
    func `recognizes runner executable arguments`(arguments: [String]) {
        #expect(TestProcessSafety.isRunningUnderTests(
            processName: "runner",
            environment: [:],
            arguments: arguments))
    }

    @Test(arguments: [
        ["/usr/local/bin/sharingan", "--account", "swift-testing"],
        ["/usr/local/bin/sharingan", "--account", "xctest"],
        ["/usr/local/bin/sharingan", "--account", "Example.xctest"],
        ["/tmp/swift-testing/sharingan", "usage"],
        ["/tmp/Example.xctest/sharingan", "usage"],
        ["/tmp/XCTestRunnerTools/sharingan", "usage"],
    ])
    func `ordinary argument values and installation paths retain production behavior`(arguments: [String]) {
        #expect(!TestProcessSafety.isRunningUnderTests(
            processName: "sharingan",
            environment: [:],
            arguments: arguments))
    }

    @Test(arguments: [
        ("swiftpm-testing-helper", [:]),
        ("SharinganPackageTests", [:]),
        ("SharinganPackageTests.xctest", [:]),
        ("Sharingan", ["XCTestConfigurationFilePath": "fixture"]),
        ("Sharingan", ["XCTestBundlePath": "fixture"]),
        ("Sharingan", ["XCTestSessionIdentifier": "fixture"]),
        ("Sharingan", ["TESTING_LIBRARY_VERSION": "fixture"]),
        ("Sharingan", ["SWIFT_TESTING": "fixture"]),
        ("Sharingan", ["SWIFT_TESTING_ENABLED": "fixture"]),
    ] as [(String, [String: String])])
    func `recognizes every supported runner signal`(
        processName: String,
        environment: [String: String])
    {
        #expect(TestProcessSafety.isRunningUnderTests(
            processName: processName,
            environment: environment))
    }

    @Test
    func `recognizes the loaded XCTest fallback without class lookup side effects`() {
        #expect(TestProcessSafety.isRunningUnderTests(
            processName: "Sharingan",
            environment: [:],
            hasLoadedXCTestCase: true))
    }

    @Test
    func `does not classify an ordinary app process as a test runner`() {
        #expect(!TestProcessSafety.isRunningUnderTests(
            processName: "Sharingan",
            environment: [:]))
    }
}
