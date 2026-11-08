import Foundation
import Testing
@testable import Sharingan

/// Regression coverage for the localized-bundle caching added for #1347.
///
/// The cache is process-global and these tests run in a parallel suite, so identity (`===`) assertions
/// would race against any other test that resolves a different language. Instead these assert the
/// concurrency-safe property that matters for correctness: every call resolves to the right `.lproj`
/// regardless of what is currently cached, so a language switch (and switch-back) is always honored and
/// the cache can never serve a stale localization.
struct LocalizationBundleCacheTests {
    @Test
    func `resolves the correct lproj per language and re-resolves on switch`() {
        resetSharinganLocalizationCacheForTesting()

        let fr = SharinganLocalizationOverride.$appLanguage.withValue("fr") {
            sharinganLocalizedBundleForTesting()
        }
        #expect(fr.bundleURL.lastPathComponent == "fr.lproj")

        // Switching language must re-resolve rather than return the cached French bundle.
        let es = SharinganLocalizationOverride.$appLanguage.withValue("es") {
            sharinganLocalizedBundleForTesting()
        }
        #expect(es.bundleURL.lastPathComponent == "es.lproj")

        // Switching back must still produce the French bundle (cache key is the language).
        let frAgain = SharinganLocalizationOverride.$appLanguage.withValue("fr") {
            sharinganLocalizedBundleForTesting()
        }
        #expect(frAgain.bundleURL.lastPathComponent == "fr.lproj")
    }

    @Test
    func `repeated same-language calls keep resolving the same lproj`() {
        resetSharinganLocalizationCacheForTesting()

        for _ in 0..<5 {
            let bundle = SharinganLocalizationOverride.$appLanguage.withValue("es") {
                sharinganLocalizedBundleForTesting()
            }
            #expect(bundle.bundleURL.lastPathComponent == "es.lproj")
        }
    }

    @Test
    func `unknown language falls back to en lproj`() {
        resetSharinganLocalizationCacheForTesting()

        let bundle = SharinganLocalizationOverride.$appLanguage.withValue("zz-unknown") {
            sharinganLocalizedBundleForTesting()
        }
        #expect(bundle.bundleURL.lastPathComponent == "en.lproj")
    }

    @Test
    func `format locale follows the resolved resource bundle`() {
        let english = SharinganLocalizationOverride.$appLanguage.withValue("en") {
            sharinganLocalizedResourceLocale()
        }
        #expect(english.language.languageCode?.identifier == "en")

        let fallback = SharinganLocalizationOverride.$appLanguage.withValue("zz-unknown") {
            sharinganLocalizedResourceLocale()
        }
        #expect(fallback.language.languageCode?.identifier == "en")
    }

    @Test
    func `resource locale expands English stringsdict singular forms`() {
        let rendered = SharinganLocalizationOverride.$appLanguage.withValue("en") {
            String(
                format: L("≈%d full 5h windows of weekly left · %d windows until reset"),
                locale: sharinganLocalizedResourceLocale(),
                arguments: [1, 1])
        }

        #expect(rendered == "≈1 full 5h window of weekly left · 1 window until reset")
    }

    @Test
    func `resolution survives an explicit cache reset`() {
        let first = SharinganLocalizationOverride.$appLanguage.withValue("uk") {
            sharinganLocalizedBundleForTesting()
        }
        #expect(first.bundleURL.lastPathComponent == "uk.lproj")

        resetSharinganLocalizationCacheForTesting()

        let afterReset = SharinganLocalizationOverride.$appLanguage.withValue("uk") {
            sharinganLocalizedBundleForTesting()
        }
        #expect(afterReset.bundleURL.lastPathComponent == "uk.lproj")
    }
}
