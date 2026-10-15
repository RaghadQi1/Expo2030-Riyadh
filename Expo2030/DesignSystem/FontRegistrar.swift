import CoreText
import Foundation

/// Registers the bundled IBM Plex fonts (SIL Open Font License, see Resources/Fonts/OFL-*.txt).
/// Done at runtime so the fonts work regardless of how Xcode lays out the bundle resources.
enum FontRegistrar {
    private static var didRegister = false

    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already registered (e.g. SwiftUI previews) is not an error worth surfacing.
                #if DEBUG
                if let error { print("Font registration skipped for \(url.lastPathComponent): \(error.takeRetainedValue())") }
                #endif
            }
        }
    }
}
