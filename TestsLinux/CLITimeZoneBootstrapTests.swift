import Foundation
import Testing
@testable import SharinganCLI

struct CLITimeZoneBootstrapTests {
    @Test
    func `derives IANA identifier from resolved zoneinfo path`() {
        #expect(SharinganCLI.linuxTimeZoneBootstrapIdentifier(
            currentValue: nil,
            localTimeReadable: true,
            resolvedLocalTimePath: "/nix/store/hash-tzdata/share/zoneinfo/America/New_York")
            == "America/New_York")
    }

    @Test(arguments: [
        ("/usr/share/zoneinfo/Europe/Berlin", "Europe/Berlin"),
        ("/usr/share/zoneinfo/posix/Australia/Sydney", "Australia/Sydney"),
        ("/usr/share/zoneinfo/right/Etc/UTC", "Etc/UTC"),
    ])
    func `normalizes conventional zoneinfo paths`(resolvedPath: String, expectedIdentifier: String) {
        #expect(SharinganCLI.linuxTimeZoneIdentifier(from: resolvedPath) == expectedIdentifier)
    }

    @Test
    func `does not bootstrap an unrecognized localtime path`() {
        #expect(SharinganCLI.linuxTimeZoneBootstrapIdentifier(
            currentValue: nil,
            localTimeReadable: true,
            resolvedLocalTimePath: "/etc/localtime") == nil)
    }

    @Test(arguments: ["Asia/Kolkata", "", ":/custom/zoneinfo"])
    func `preserves caller timezone`(currentValue: String) {
        #expect(SharinganCLI.linuxTimeZoneBootstrapIdentifier(
            currentValue: currentValue,
            localTimeReadable: true,
            resolvedLocalTimePath: "/nix/store/hash-tzdata/share/zoneinfo/Asia/Kolkata") == nil)
    }

    @Test
    func `does not set an unreadable localtime file`() {
        #expect(SharinganCLI.linuxTimeZoneBootstrapIdentifier(
            currentValue: nil,
            localTimeReadable: false,
            resolvedLocalTimePath: "/nix/store/hash-tzdata/share/zoneinfo/Asia/Kolkata") == nil)
    }

    @Test(arguments: [
        "/nix/store/hash-tzdata/share/zoneinfo/",
        "/nix/store/hash-tzdata/share/zoneinfo/../UTC",
        "/var/lib/timezone/Asia/Kolkata",
    ])
    func `rejects invalid or unrelated resolved paths`(resolvedPath: String) {
        #expect(SharinganCLI.linuxTimeZoneIdentifier(from: resolvedPath) == nil)
    }

    @Test
    func `rejects invalid CoreFoundation timezone data`() {
        #expect(!SharinganCLI.primeCoreFoundationTimeZone(
            identifier: "Etc/SharinganInvalid",
            filePath: "/dev/null"))
    }

    #if os(Linux)
    @Test
    func `primes the legacy formatter bridge with system timezone data`() throws {
        let resolvedPath = URL(fileURLWithPath: "/etc/localtime").resolvingSymlinksInPath().path
        guard let identifier = SharinganCLI.linuxTimeZoneIdentifier(from: resolvedPath) else { return }

        #expect(SharinganCLI.primeCoreFoundationTimeZone(
            identifier: identifier,
            filePath: "/etc/localtime"))

        let timeZone = try #require(TimeZone(identifier: identifier))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        #expect(!formatter.string(from: Date(timeIntervalSince1970: 0)).isEmpty)
    }
    #endif
}
