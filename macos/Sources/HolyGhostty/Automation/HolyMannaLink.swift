import Foundation

/// Shared by terminal hit testing and the read-only automation route.
enum HolyMannaLink {
    private static let pattern = try? NSRegularExpression(pattern: #"(?<!\w)mn-[a-f0-9]{6,}(?!\w)"#)
    private static let paintCandidate = try? NSRegularExpression(pattern: #"mn-[a-f0-9]*|mn?$"#)

    static func match(in text: String, atUTF16Offset offset: Int) -> NSRange? {
        let length = (text as NSString).length
        guard offset >= 0, offset < length else { return nil }
        return pattern?.matches(in: text, range: NSRange(location: 0, length: length))
            .first { NSLocationInRange(offset, $0.range) }?.range
    }

    struct Viewport: Equatable {
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

    /// All inputs are core point coordinates. Adjacent selection origins give
    /// cell width; IME height gives cell height. A one-column grid always has
    /// cursor column zero, whose IME x anchor is the cell's midpoint.
    static func viewport(columns: Int, rows: Int, baseline: CGPoint, nextColumnX: CGFloat?,
                         imeAnchor: CGPoint, cellHeight: CGFloat) -> Viewport? {
        guard columns > 0, rows > 0, columns == 1 || nextColumnX != nil else { return nil }
        let width = nextColumnX.map { $0 - baseline.x } ?? 2 * (imeAnchor.x - baseline.x)
        guard width.isFinite, width > 0,
              let origin = gridOrigin(baseline: baseline, imeCellBottom: imeAnchor.y, cellHeight: cellHeight) else { return nil }
        return .init(columns: columns, rows: rows, baseline: baseline, gridOrigin: origin,
                     cellSize: CGSize(width: width, height: cellHeight))
    }

    /// Resolve candidates using prefixes of their own physical row. A spinner
    /// above that row must not poison the cell mapping. Read across row edges
    /// only while an identifier can continue, preserving core soft-wrap rules.
    static func paintRuns(in viewport: Viewport, row: Int, text: String,
                          readCells: (ClosedRange<Int>) -> String?) -> [PaintRun]? {
        guard viewport.columns > 0, viewport.rows > 0,
              viewport.cellSize.width > 0, viewport.cellSize.height > 0 else { return nil }
        let source = text as NSString
        let candidates = paintCandidate?.matches(in: text, range: NSRange(location: 0, length: source.length)) ?? []
        let rowStart = row * viewport.columns
        let finalCell = viewport.columns * viewport.rows - 1
        var prefixLengths: [Int: Int] = [:]
        func prefixLength(_ cell: Int) -> Int? {
            if let cached = prefixLengths[cell] { return cached }
            guard let prefix = readCells(rowStart...cell), source.hasPrefix(prefix) else { return nil }
            let length = (prefix as NSString).length
            prefixLengths[cell] = length
            return length
        }
        var result: [PaintRun] = []
        for candidate in candidates {
            var lower = rowStart
            var upper = rowStart + viewport.columns - 1
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                guard let length = prefixLength(middle) else { return nil }
                if length <= candidate.range.location { lower = middle + 1 } else { upper = middle }
            }
            guard prefixLength(lower) == candidate.range.location + 1 else { return nil }
            var end = rowStart + viewport.columns - 1
            guard var tail = readCells(lower...end) else { return nil }
            while end < finalCell, canContinueIdentifier(tail) {
                end += viewport.columns
                guard let extended = readCells(lower...end) else { return nil }
                tail = extended
            }
            guard let match = match(in: tail, atUTF16Offset: 0), match.location == 0 else { continue }
            let id = (tail as NSString).substring(with: match)
            let last = lower + id.utf16.count - 1
            guard last <= finalCell, readCells(lower...last) == id,
                  let context = readCells(max(0, lower - 1)...min(finalCell, last + 1)) else { return nil }
            // Include the cells on both sides, even over a soft wrap, so a
            // row beginning with mn-abcdef cannot link inside a longer word.
            let range = (context as NSString).range(of: id)
            guard range.location != NSNotFound,
                  self.match(in: context, atUTF16Offset: range.location) == range else { continue }
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

    private static func canContinueIdentifier(_ text: String) -> Bool {
        text == "m" || text == "mn" || (text.hasPrefix("mn-") && text.utf8.dropFirst(3).allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        })
    }

    /// Accepted rows survive transient changes and failed reads. A row can
    /// gain paint after two equal samples regardless of every other row.
    /// Each replacement is returned as one complete set of runs.
    struct RowPaintState {
        private struct PaintedRow {
            let dependencies: [Int: String]
            let runs: [PaintRun]
        }
        private var previous: [Int: String] = [:]
        private var painted: [Int: PaintedRow] = [:]

        mutating func sample(_ viewport: Viewport, readCells: (ClosedRange<Int>) -> String?) -> [PaintRun] {
            var current: [Int: String] = [:]
            for row in 0..<viewport.rows {
                current[row] = readCells(row * viewport.columns...(row + 1) * viewport.columns - 1)
            }
            defer { previous = current }
            for row in 0..<viewport.rows {
                guard let text = current[row], previous[row] == text else { continue }
                if let cached = painted[row], cached.dependencies.allSatisfy({ current[$0.key] == $0.value }) {
                    continue
                }
                var dependencies: Set<Int> = [row]
                guard let runs = paintRuns(in: viewport, row: row, text: text, readCells: { cells in
                    dependencies.formUnion(cells.lowerBound / viewport.columns...cells.upperBound / viewport.columns)
                    return readCells(cells)
                }) else { continue }
                let lastRow = runs.map { Int(round(($0.rect.minY - viewport.gridOrigin.y) / viewport.cellSize.height)) }.max() ?? row
                // Neighbouring text affects word boundaries. Recompute when
                // it changes, but only the rows carrying paint must settle.
                guard (row...lastRow).allSatisfy({ current[$0] != nil && current[$0] == previous[$0] }),
                      (row...lastRow).allSatisfy({
                          current[$0] == readCells($0 * viewport.columns...($0 + 1) * viewport.columns - 1)
                      }) else { continue }
                painted[row] = PaintedRow(dependencies: current.filter { dependencies.contains($0.key) }, runs: runs)
            }
            return painted.keys.sorted().flatMap { painted[$0]?.runs ?? [] }
        }

        mutating func invalidate() {
            previous = [:]
            painted = [:]
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
