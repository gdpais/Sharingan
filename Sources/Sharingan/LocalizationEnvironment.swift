import Foundation
import SwiftUI

func sharinganLocalizedLayoutDirection() -> LayoutDirection {
    Locale.Language(identifier: sharinganLocalizedResourceLocale().identifier).characterDirection == .rightToLeft
        ? .rightToLeft : .leftToRight
}

private struct SharinganLocalizationEnvironment: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(
                \.locale,
                sharinganLocalizationSignature().isEmpty
                    ? sharinganLocalizedLocale() : sharinganLocalizedResourceLocale())
            .environment(\.layoutDirection, sharinganLocalizedLayoutDirection())
    }
}

extension View {
    /// Keep native formatting and layout in the same language as the selected string resources.
    func sharinganLocalized() -> some View {
        self.modifier(SharinganLocalizationEnvironment())
    }
}
