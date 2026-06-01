enum GhosttyIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appUnavailable
    case surfaceNotFound
    case permissionDenied

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appUnavailable: "The Holy Ghostty app isn't properly initialized."
        case .surfaceNotFound: "The terminal no longer exists."
        case .permissionDenied: "Holy Ghostty doesn't allow Shortcuts."
        }
    }
}
