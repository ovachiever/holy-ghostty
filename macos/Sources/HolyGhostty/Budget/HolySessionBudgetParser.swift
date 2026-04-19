import Foundation

enum HolySessionBudgetParser {
    static func updatedTelemetry(
        from preview: String,
        current: HolySessionBudgetTelemetry
    ) -> HolySessionBudgetTelemetry? {
        let lines = preview
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        var parsedInputTokens: Int?
        var parsedOutputTokens: Int?
        var parsedTotalTokens: Int?
        var parsedCostUSD: Double?
        var evidence: String?

        for line in lines.reversed() {
            if parsedInputTokens == nil {
                parsedInputTokens = firstIntMatch(
                    in: line,
                    patterns: [
                        #"(?:input|prompt)\s+tokens?\D+([0-9][0-9,]*)"#,
                        #"([0-9][0-9,]*)\s+(?:input|prompt)\s+tokens?"#,
                    ]
                )
            }

            if parsedOutputTokens == nil {
                parsedOutputTokens = firstIntMatch(
                    in: line,
                    patterns: [
                        #"(?:output|completion)\s+tokens?\D+([0-9][0-9,]*)"#,
                        #"([0-9][0-9,]*)\s+(?:output|completion)\s+tokens?"#,
                    ]
                )
            }

            if parsedTotalTokens == nil {
                parsedTotalTokens = firstIntMatch(
                    in: line,
                    patterns: [
                        #"total\s+tokens?\D+([0-9][0-9,]*)"#,
                        #"([0-9][0-9,]*)\s+total\s+tokens?"#,
                        #"tokens?\D+([0-9][0-9,]*)"#,
                    ]
                )
            }

            if parsedCostUSD == nil {
                parsedCostUSD = firstDoubleMatch(
                    in: line,
                    patterns: [
                        #"(?:total\s+)?cost\D+\$?([0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?)"#,
                        #"\$([0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?)"#,
                    ]
                )
            }

            if evidence == nil,
               parsedInputTokens != nil || parsedOutputTokens != nil || parsedTotalTokens != nil || parsedCostUSD != nil {
                evidence = line
            }
        }

        guard parsedInputTokens != nil || parsedOutputTokens != nil || parsedTotalTokens != nil || parsedCostUSD != nil else {
            return nil
        }

        var next = current
        next.inputTokens = parsedInputTokens ?? current.inputTokens
        next.outputTokens = parsedOutputTokens ?? current.outputTokens
        next.totalTokens = parsedTotalTokens
            ?? {
                if parsedInputTokens != nil || parsedOutputTokens != nil {
                    return (parsedInputTokens ?? 0) + (parsedOutputTokens ?? 0)
                }
                return current.totalTokens
            }()
        next.estimatedCostUSD = parsedCostUSD ?? current.estimatedCostUSD
        next.evidence = evidence ?? current.evidence

        if next != current {
            next.lastUpdatedAt = .now
            return next
        }

        return nil
    }

    private static func firstIntMatch(in text: String, patterns: [String]) -> Int? {
        for pattern in patterns {
            if let value = firstMatch(in: text, pattern: pattern) {
                return Int(value.replacingOccurrences(of: ",", with: ""))
            }
        }
        return nil
    }

    private static func firstDoubleMatch(in text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            if let value = firstMatch(in: text, pattern: pattern) {
                return Double(value.replacingOccurrences(of: ",", with: ""))
            }
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[valueRange])
    }
}
