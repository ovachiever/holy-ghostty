import Foundation

/// Shared by terminal hit testing and the read-only automation route.
enum HolyMannaLink {
    private static let pattern = try? NSRegularExpression(pattern: #"(?<!\w)mn-[a-f0-9]{6,}(?!\w)"#)

    static func match(in text: String, atUTF16Offset offset: Int) -> NSRange? {
        let length = (text as NSString).length
        guard offset >= 0, offset < length else { return nil }
        return pattern?.matches(in: text, range: NSRange(location: 0, length: length))
            .first { NSLocationInRange(offset, $0.range) }?.range
    }

    static func isIdentifier(_ text: String) -> Bool {
        match(in: text, atUTF16Offset: 0) == NSRange(location: 0, length: (text as NSString).length)
    }

    /// Core word selections can soft-wrap with punctuation attached. An ASCII
    /// word shorter than a row identifies the clicked cell by column alone.
    /// For longer words, every possible cell must name the same match.
    static func wrappedMatch(in text: String, startingAt cell: Int, columns: Int, clickedColumn: Int) -> NSRange? {
        guard cell >= 0, columns > 0, (0..<columns).contains(clickedColumn),
              text.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return nil }
        var offset = (clickedColumn - cell % columns + columns) % columns
        var selected: NSRange?
        while offset < text.utf8.count {
            guard let match = match(in: text, atUTF16Offset: offset),
                  selected == nil || selected == match else { return nil }
            selected = match
            offset += columns
        }
        return selected
    }

    static func url(for id: String) -> URL? {
        guard isIdentifier(id) else { return nil }
        return URL(string: "holy-ghostty://board?item=\(id)")
    }

    /// ASCII ids occupy one cell per character. The origin is the first
    /// column's baseline on the first row, in viewport points.
    static func underlines(for id: String, startingAt cell: Int, columns: Int,
                           origin: CGPoint, cellSize: CGSize) -> [CGRect] {
        guard isIdentifier(id), cell >= 0, columns > 0,
              cellSize.width > 0, cellSize.height > 0 else { return [] }
        var cursor = cell
        var remaining = id.count
        var result: [CGRect] = []
        while remaining > 0 {
            let count = min(remaining, columns - cursor % columns)
            result.append(CGRect(x: origin.x + CGFloat(cursor % columns) * cellSize.width,
                                 y: origin.y + CGFloat(cursor / columns) * cellSize.height + 1,
                                 width: CGFloat(count) * cellSize.width, height: 1))
            cursor += count
            remaining -= count
        }
        return result
    }
}
