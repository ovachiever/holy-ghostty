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

    struct Viewport: Equatable {
        let text: String
        let columns: Int
        let rows: Int
        let baseline: CGPoint
        let gridOrigin: CGPoint
        let cellSize: CGSize
    }

    struct PaintRun: Equatable {
        let text: String
        let rect: CGRect
        let baseline: CGPoint
    }

    /// Both C APIs return points in top-left coordinates. The IME anchor is
    /// the bottom of a cursor cell, hence congruent to every row edge. Pair it
    /// with row zero's baseline to recover the actual padding, even when the
    /// cursor is offscreen or top padding exceeds a cell (e.g. 34,2).
    static func gridOrigin(baseline: CGPoint, imeCellBottom: CGFloat, cellHeight: CGFloat) -> CGPoint? {
        guard baseline.x.isFinite, baseline.y.isFinite, imeCellBottom.isFinite,
              cellHeight.isFinite, cellHeight > 0 else { return nil }
        var ascent = (baseline.y - imeCellBottom).truncatingRemainder(dividingBy: cellHeight)
        if ascent <= 0 { ascent += cellHeight }
        return CGPoint(x: baseline.x, y: baseline.y - ascent)
    }

    /// Map UTF-16 matches back through core cell selections. No wcwidth or
    /// Swift character count is substituted for the terminal's Unicode map.
    /// Non-rectangular reads unwrap soft wraps and retain hard newlines.
    static func paintRuns(in viewport: Viewport, readPrefix: (Int) -> String?) -> [PaintRun]? {
        guard viewport.columns > 0, viewport.rows > 0,
              viewport.cellSize.width > 0, viewport.cellSize.height > 0 else { return nil }
        let source = viewport.text as NSString
        let matches = pattern?.matches(in: viewport.text, range: NSRange(location: 0, length: source.length)) ?? []
        var prefixLengths: [Int: Int] = [:]
        func prefixLength(_ cell: Int) -> Int? {
            if let cached = prefixLengths[cell] { return cached }
            guard let prefix = readPrefix(cell), source.hasPrefix(prefix) else { return nil }
            let length = (prefix as NSString).length
            prefixLengths[cell] = length
            return length
        }
        var result: [PaintRun] = []
        for match in matches {
            var lower = 0
            var upper = viewport.columns * viewport.rows - 1
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                guard let length = prefixLength(middle) else { return nil }
                if length <= match.range.location { lower = middle + 1 } else { upper = middle }
            }
            let last = lower + match.range.length - 1
            guard last < viewport.columns * viewport.rows,
                  prefixLength(lower) == match.range.location + 1,
                  prefixLength(last) == NSMaxRange(match.range) else { return nil }
            let id = source.substring(with: match.range)
            var cursor = lower
            var offset = 0
            while offset < id.count {
                let count = min(id.count - offset, viewport.columns - cursor % viewport.columns)
                let x = CGFloat(cursor % viewport.columns) * viewport.cellSize.width
                let y = CGFloat(cursor / viewport.columns) * viewport.cellSize.height
                result.append(PaintRun(
                    text: (id as NSString).substring(with: NSRange(location: offset, length: count)),
                    rect: CGRect(x: viewport.gridOrigin.x + x, y: viewport.gridOrigin.y + y,
                                 width: CGFloat(count) * viewport.cellSize.width, height: viewport.cellSize.height),
                    baseline: CGPoint(x: viewport.baseline.x + x, y: viewport.baseline.y + y)))
                cursor += count
                offset += count
            }
        }
        return result
    }

    /// A changed sample removes the old overlay immediately. Only a second
    /// identical sample is eligible for painting; callers sample 100ms apart.
    struct ViewportStability {
        enum Observation { case clear, paint, keep }
        private var pending: Viewport?
        private var painted = false

        mutating func observe(_ viewport: Viewport?) -> Observation {
            guard let viewport else {
                invalidate()
                return .clear
            }
            guard viewport == pending else {
                pending = viewport
                painted = false
                return .clear
            }
            return painted ? .keep : .paint
        }

        mutating func didPaint() { painted = true }

        mutating func invalidate() {
            pending = nil
            painted = false
        }
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
