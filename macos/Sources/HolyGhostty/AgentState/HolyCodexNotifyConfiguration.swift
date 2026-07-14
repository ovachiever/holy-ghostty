import Foundation

enum HolyCodexNotifyConfigurationError: Error, Equatable, LocalizedError {
    case foreignNotify
    case ambiguousNotify

    var errorDescription: String? {
        switch self {
        case .foreignNotify:
            "Codex already has a user-level notify command; Holy will not overwrite or chain it"
        case .ambiguousNotify:
            "Codex's user-level notify setting is multiline or ambiguous; Holy cannot update it safely"
        }
    }
}

extension HolyAgentStateBridge {
    static func codexNotifyConfigurationLine(adapterURL: URL) -> String {
        "notify = [\(tomlBasicString(adapterURL.path))]"
    }

    static func mergingCodexConfiguration(
        _ contents: String,
        adapterURL: URL
    ) throws -> String {
        guard !contents.unicodeScalars.contains(where: { $0.value == 0xFEFF }) else {
            throw HolyCodexNotifyConfigurationError.ambiguousNotify
        }
        let block = codexNotifyConfigurationBlock(adapterURL: adapterURL)
        if let remainder = ownedCodexNotifyRemainder(
            contents,
            adapterURL: adapterURL
        ) {
            switch topLevelNotifyState(in: remainder) {
            case .absent:
                return contents
            case .multiline:
                throw HolyCodexNotifyConfigurationError.ambiguousNotify
            case .singleLine:
                throw HolyCodexNotifyConfigurationError.foreignNotify
            }
        }

        switch topLevelNotifyState(in: contents) {
        case .absent:
            return contents.isEmpty ? block + "\n" : block + "\n\n" + contents
        case .multiline:
            throw HolyCodexNotifyConfigurationError.ambiguousNotify
        case .singleLine:
            throw HolyCodexNotifyConfigurationError.foreignNotify
        }
    }

    static func removingCodexConfiguration(
        _ contents: String,
        adapterURL: URL
    ) throws -> String {
        guard !contents.unicodeScalars.contains(where: { $0.value == 0xFEFF }) else {
            throw HolyCodexNotifyConfigurationError.ambiguousNotify
        }
        if let remainder = ownedCodexNotifyRemainder(
            contents,
            adapterURL: adapterURL
        ) {
            switch topLevelNotifyState(in: remainder) {
            case .absent:
                return remainder
            case .multiline:
                throw HolyCodexNotifyConfigurationError.ambiguousNotify
            case .singleLine:
                throw HolyCodexNotifyConfigurationError.foreignNotify
            }
        }
        switch topLevelNotifyState(in: contents) {
        case .absent:
            return contents
        case .multiline:
            throw HolyCodexNotifyConfigurationError.ambiguousNotify
        case .singleLine:
            throw HolyCodexNotifyConfigurationError.foreignNotify
        }
    }

    private enum TopLevelNotifyState {
        case absent
        case singleLine
        case multiline
    }

    private static func codexNotifyConfigurationBlock(adapterURL: URL) -> String {
        codexNotifyConfigurationMarker + "\n" + codexNotifyConfigurationLine(adapterURL: adapterURL)
    }

    /// Holy inserts its exact-owned block before all user content. Keeping the
    /// ownership boundary byte-exact makes uninstall reversible without a TOML
    /// reserializer that would destroy comments and formatting.
    private static func ownedCodexNotifyRemainder(
        _ contents: String,
        adapterURL: URL
    ) -> String? {
        let block = codexNotifyConfigurationBlock(adapterURL: adapterURL)
        if contents == block || contents == block + "\n" {
            return ""
        }
        let separated = block + "\n\n"
        if contents.hasPrefix(separated) {
            return String(contents.dropFirst(separated.count))
        }
        let continued = block + "\n"
        guard contents.hasPrefix(continued) else { return nil }
        return String(contents.dropFirst(continued.count))
    }

    /// This is intentionally a narrow recognizer, not a general TOML parser.
    /// It follows strings and container depth closely enough to distinguish a
    /// real top-level assignment from text in comments, multiline strings,
    /// arrays, and tables. Any notify shape other than one physical assignment
    /// is classified as ambiguous and blocks mutation.
    private static func topLevelNotifyState(in contents: String) -> TopLevelNotifyState {
        var multiline: Character?
        var squareDepth = 0
        var braceDepth = 0
        var enteredTable = false
        var result: TopLevelNotifyState = .absent

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let startsAtTopLevel = multiline == nil && squareDepth == 0 && braceDepth == 0
            if startsAtTopLevel && !enteredTable {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    if trimmed.hasPrefix("[") {
                        if tableHeaderTargetsNotify(trimmed) {
                            return .singleLine
                        }
                        enteredTable = true
                    } else if isNotifyAssignmentPrefix(trimmed) {
                        if result != .absent {
                            return .multiline
                        }
                        result = notifyAssignmentIsSingleLine(trimmed) ? .singleLine : .multiline
                    }
                }
            }

            scanTomlLine(
                line,
                multiline: &multiline,
                squareDepth: &squareDepth,
                braceDepth: &braceDepth
            )
        }
        return result
    }

    private static func isNotifyAssignmentPrefix(_ line: String) -> Bool {
        for key in ["notify", "\"notify\"", "'notify'"] where line.hasPrefix(key) {
            let remainder = line.dropFirst(key.count)
            guard let first = remainder.first else { continue }
            if first == "." { return true }
            if first == "=" || first == " " || first == "\t" {
                let trimmed = remainder.drop(while: { $0 == " " || $0 == "\t" })
                if trimmed.first == "=" { return true }
            }
        }
        return false
    }

    private static func tableHeaderTargetsNotify(_ line: String) -> Bool {
        var body = line.dropFirst()
        if body.first == "[" { body = body.dropFirst() }
        body = body.drop(while: { $0 == " " || $0 == "\t" })
        for key in ["notify", "\"notify\"", "'notify'"] where body.hasPrefix(key) {
            let remainder = body.dropFirst(key.count)
            guard let first = remainder.first else { continue }
            if first == "." || first == "]" || first == " " || first == "\t" {
                return true
            }
        }
        return false
    }

    private static func notifyAssignmentIsSingleLine(_ line: String) -> Bool {
        guard let equals = line.firstIndex(of: "=") else { return false }
        let rhs = line[line.index(after: equals)...]
            .trimmingCharacters(in: .whitespaces)
        guard rhs.hasPrefix("[") else { return true }

        var quote: Character?
        var escaped = false
        var depth = 0
        for character in rhs {
            if let active = quote {
                if active == "\"" && character == "\\" && !escaped {
                    escaped = true
                } else if character == active && !escaped {
                    quote = nil
                } else {
                    escaped = false
                }
                continue
            }
            if character == "#" { break }
            if character == "\"" || character == "'" {
                quote = character
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
            }
        }
        return quote == nil && depth == 0
    }

    private static func scanTomlLine(
        _ line: String,
        multiline: inout Character?,
        squareDepth: inout Int,
        braceDepth: inout Int
    ) {
        let characters = Array(line)
        var index = 0
        var quote: Character?
        var escaped = false

        while index < characters.count {
            if let active = multiline {
                if index + 2 < characters.count,
                   characters[index] == active,
                   characters[index + 1] == active,
                   characters[index + 2] == active {
                    multiline = nil
                    index += 3
                } else {
                    index += 1
                }
                continue
            }
            if let active = quote {
                let character = characters[index]
                if active == "\"" && character == "\\" && !escaped {
                    escaped = true
                } else if character == active && !escaped {
                    quote = nil
                } else {
                    escaped = false
                }
                index += 1
                continue
            }

            let character = characters[index]
            if character == "#" { break }
            if character == "\"" || character == "'",
               index + 2 < characters.count,
               characters[index + 1] == character,
               characters[index + 2] == character {
                multiline = character
                index += 3
            } else if character == "\"" || character == "'" {
                quote = character
                index += 1
            } else {
                if character == "[" { squareDepth += 1 }
                if character == "]" { squareDepth = max(0, squareDepth - 1) }
                if character == "{" { braceDepth += 1 }
                if character == "}" { braceDepth = max(0, braceDepth - 1) }
                index += 1
            }
        }
    }

    private static func tomlBasicString(_ value: String) -> String {
        var escaped = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: escaped += "\\b"
            case 0x09: escaped += "\\t"
            case 0x0A: escaped += "\\n"
            case 0x0C: escaped += "\\f"
            case 0x0D: escaped += "\\r"
            case 0x22: escaped += "\\\""
            case 0x5C: escaped += "\\\\"
            case 0x00 ... 0x07, 0x0B, 0x0E ... 0x1F, 0x7F:
                escaped += String(format: "\\u%04X", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        escaped += "\""
        return escaped
    }
}
