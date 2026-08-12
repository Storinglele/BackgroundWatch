import Foundation

/// SwiftPM ships localized strings in a module bundle, which SwiftUI's implicit
/// `Text("key")` lookup would miss because it searches `Bundle.main`.
///
/// The lproj is resolved against the user's language list directly instead of relying on
/// `Bundle.module.localizedString`, whose choice follows the *main* bundle's declared
/// localizations — empty when running the bare executable via `swift run`.
private let stringsBundle: Bundle = {
    let available = Bundle.module.localizations
    guard let best = Bundle.preferredLocalizations(from: available).first,
          let path = Bundle.module.path(forResource: best, ofType: "lproj"),
          let bundle = Bundle(path: path)
    else { return .module }
    return bundle
}()

func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = stringsBundle.localizedString(forKey: key, value: key, table: nil)
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}
