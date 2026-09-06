import Foundation
import SwiftUI

/// app.js grips: every fixed column of a ledger is fitted to its widest
/// cell, and the user may drag its right edge. Version 2 stores the result
/// as a share of the ledger width, so a preference made on a large display
/// cannot force the same pixel width into a smaller window.
struct HolyLedgerColumnOverrides: Equatable {
    private struct Payload: Codable {
        let version: Int
        let proportions: [String: Double]
    }

    private static let version = 2
    private static let legacyReferenceWidth: CGFloat = 1_440
    private(set) var proportions: [String: CGFloat] = [:]

    init(json: String) {
        guard let data = json.data(using: .utf8) else { return }
        if let payload = try? JSONDecoder().decode(Payload.self, from: data),
           payload.version == Self.version {
            proportions = Self.validProportions(payload.proportions)
            return
        }
        guard let legacy = try? JSONDecoder().decode([String: Double].self, from: data) else { return }
        proportions = Self.validProportions(
            legacy.mapValues { $0 / Double(Self.legacyReferenceWidth) }
        )
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = Payload(
            version: Self.version,
            proportions: proportions.mapValues(Double.init)
        )
        let data = (try? encoder.encode(payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// The fitted width unless the user dragged this column. A stored
    /// proportion is always resolved against the pane that owns the row.
    func width(_ column: String, fitted: CGFloat, availableWidth: CGFloat) -> CGFloat {
        guard let proportion = proportions[column], availableWidth > 0 else { return fitted }
        return min(availableWidth, proportion * availableWidth)
    }

    func hasOverride(_ column: String) -> Bool {
        proportions[column] != nil
    }

    mutating func set(_ column: String, width: CGFloat, availableWidth: CGFloat) {
        guard width.isFinite, availableWidth.isFinite, width > 0, availableWidth > 0 else {
            proportions[column] = nil
            return
        }
        proportions[column] = min(1, width / availableWidth)
    }

    mutating func reset(_ column: String) {
        proportions[column] = nil
    }

    private static func validProportions(_ values: [String: Double]) -> [String: CGFloat] {
        values.reduce(into: [:]) { result, entry in
            let value = CGFloat(entry.value)
            guard value.isFinite, value > 0 else { return }
            result[entry.key] = min(1, value)
        }
    }
}

struct HolyLedgerFixedColumn: Equatable, Sendable {
    let id: String
    let fittedWidth: CGFloat
    let minimumWidth: CGFloat
}

struct HolyLedgerResolvedColumns: Equatable, Sendable {
    let availableWidth: CGFloat
    let minimumFlexibleWidth: CGFloat
    let flexibleWidth: CGFloat
    let chromeWidth: CGFloat
    let discardedStoredWidths: Bool
    private let widths: [String: CGFloat]

    init(
        availableWidth: CGFloat,
        minimumFlexibleWidth: CGFloat,
        flexibleWidth: CGFloat,
        chromeWidth: CGFloat,
        discardedStoredWidths: Bool,
        widths: [String: CGFloat]
    ) {
        self.availableWidth = availableWidth
        self.minimumFlexibleWidth = minimumFlexibleWidth
        self.flexibleWidth = flexibleWidth
        self.chromeWidth = chromeWidth
        self.discardedStoredWidths = discardedStoredWidths
        self.widths = widths
    }

    func width(_ column: String, fallback: CGFloat = 0) -> CGFloat {
        widths[column] ?? fallback
    }

    func widths(includingFlexibleColumn flexibleColumn: String) -> [String: CGFloat] {
        var result = widths
        result[flexibleColumn] = flexibleWidth
        return result
    }

    var occupiedWidth: CGFloat {
        chromeWidth + flexibleWidth + widths.values.reduce(0, +)
    }
}

/// One responsive law for the Board and Archive ledgers. The flexible text
/// column receives its readable floor first. A stored layout that would starve
/// that floor is discarded and content-fit widths are restored. If the fit is
/// still too wide, every column yields proportionally toward its semantic
/// floor. GeometryReader supplies the current window width, so a resize or
/// screen move recomputes the result.
enum HolyLedgerResponsiveLayout {
    static let inspectorFraction: CGFloat = 0.35

    static func showsInlineInspector(windowWidth: CGFloat) -> Bool {
        windowWidth > HolyMannaBoardMetrics.compactBreakpoint
    }

    static func showsSecondaryColumn(windowWidth: CGFloat) -> Bool {
        windowWidth > HolyMannaBoardMetrics.narrowBreakpoint
    }

    static func inspectorWidth(
        windowWidth: CGFloat,
        persistedWidth: CGFloat,
        narrowWidth: CGFloat = HolyMannaBoardMetrics.inspectorNarrowWidth,
        minimumWidth: CGFloat = HolyMannaBoardMetrics.inspectorMinimumWidth,
        maximumWidth: CGFloat = HolyMannaBoardMetrics.inspectorMaximumWidth
    ) -> CGFloat {
        let bounds = inspectorWidthBounds(
            windowWidth: windowWidth,
            narrowWidth: narrowWidth,
            minimumWidth: minimumWidth,
            maximumWidth: maximumWidth
        )
        return min(bounds.upperBound, max(bounds.lowerBound, persistedWidth))
    }

    static func inspectorWidthBounds(
        windowWidth: CGFloat,
        narrowWidth: CGFloat = HolyMannaBoardMetrics.inspectorNarrowWidth,
        minimumWidth: CGFloat = HolyMannaBoardMetrics.inspectorMinimumWidth,
        maximumWidth: CGFloat = HolyMannaBoardMetrics.inspectorMaximumWidth
    ) -> ClosedRange<CGFloat> {
        let proportionalCap = max(0, windowWidth * inspectorFraction)
        let breakpointCap = windowWidth <= HolyMannaBoardMetrics.narrowBreakpoint
            ? narrowWidth
            : maximumWidth
        let cap = min(maximumWidth, min(proportionalCap, breakpointCap))
        return minimumWidth ... max(minimumWidth, cap)
    }

    static func compactInspectorWidth(windowWidth: CGFloat, pagePadding: CGFloat) -> CGFloat {
        max(0, min(HolyMannaBoardMetrics.inspectorMaximumWidth, windowWidth - 2 * pagePadding))
    }

    static func columns(
        availableWidth: CGFloat,
        gap: CGFloat,
        stripeWidth: CGFloat,
        minimumFlexibleWidth: CGFloat,
        fixedColumns: [HolyLedgerFixedColumn],
        overrides: HolyLedgerColumnOverrides,
        transientWidths: [String: CGFloat]? = nil,
        transientFlexibleWidth: CGFloat? = nil
    ) -> HolyLedgerResolvedColumns {
        let available = max(0, availableWidth)
        let chrome = stripeWidth + CGFloat(fixedColumns.count + 1) * gap
        let requestedFlexible = min(minimumFlexibleWidth, max(0, available - chrome))
        let fixedBudget = max(0, available - chrome - requestedFlexible)

        if let transientWidths {
            let widths = fixedColumns.reduce(into: [String: CGFloat]()) { result, column in
                let transient = transientWidths[column.id]
                result[column.id] = transient?.isFinite == true
                    ? max(0, transient ?? 0)
                    : max(column.minimumWidth, column.fittedWidth)
            }
            let fixedTotal = widths.values.reduce(0, +)
            let transientFlexible = transientFlexibleWidth?.isFinite == true
                ? max(0, transientFlexibleWidth ?? 0)
                : max(0, available - chrome - fixedTotal)
            return .init(
                availableWidth: available,
                minimumFlexibleWidth: requestedFlexible,
                flexibleWidth: transientFlexible,
                chromeWidth: chrome,
                discardedStoredWidths: false,
                widths: widths
            )
        }

        var widths = fixedColumns.reduce(into: [String: CGFloat]()) { result, column in
            let preferred = overrides.width(
                column.id,
                fitted: column.fittedWidth,
                availableWidth: available
            )
            result[column.id] = max(column.minimumWidth, preferred)
        }

        // Stored widths are never discarded wholesale: nuking them to
        // content-fit made every release near the budget edge snap the whole
        // table (33 years of table UX say a divider you dropped stays where
        // you dropped it). Overflow is handled by the proportional shrink
        // below — columns keep their relative placement and yield only what
        // the window genuinely cannot hold.
        let storedWidthsStarveFlex = fixedColumns.contains { overrides.hasOverride($0.id) }
            && widths.values.reduce(0, +) > fixedBudget

        var deficit = max(0, widths.values.reduce(0, +) - fixedBudget)
        let shrinkRoom = fixedColumns.reduce(0) { total, column in
            total + max(0, (widths[column.id] ?? 0) - column.minimumWidth)
        }
        if deficit > 0, shrinkRoom > 0 {
            let fraction = min(1, deficit / shrinkRoom)
            for column in fixedColumns {
                let current = widths[column.id] ?? 0
                let room = max(0, current - column.minimumWidth)
                widths[column.id] = current - fraction * room
            }
            deficit = max(0, deficit - fraction * shrinkRoom)
        }

        if deficit > 0 {
            let total = widths.values.reduce(0, +)
            let scale = total > 0 ? max(0, (total - deficit) / total) : 0
            widths = widths.mapValues { $0 * scale }
        }

        let fixedTotal = widths.values.reduce(0, +)
        let flexible = max(0, available - chrome - fixedTotal)
        return .init(
            availableWidth: available,
            minimumFlexibleWidth: requestedFlexible,
            flexibleWidth: flexible,
            chromeWidth: chrome,
            discardedStoredWidths: storedWidthsStarveFlex,
            widths: widths
        )
    }
}

/// A physical divider is always the same transaction: its left neighbor gains
/// exactly the width its right neighbor yields. Flexible text columns are
/// explicit participants, never invisible compensation routed from elsewhere.
struct HolyLedgerColumnBoundary: Equatable, Sendable {
    let leading: String
    let trailing: String
    let gripOnLeadingEdge: Bool

    var columns: [String] { [leading, trailing] }

    func resizedWidths(
        from startingWidths: [String: CGFloat],
        minimumWidths: [String: CGFloat],
        translation: CGFloat
    ) -> [String: CGFloat] {
        let delta = translation.rounded()
        let leadingStart = startingWidths[leading] ?? 0
        let trailingStart = startingWidths[trailing] ?? 0
        // A responsive layout may already be below its semantic floor. Treat
        // the captured width as the floor in that degraded state so grabbing a
        // divider never jumps the table before the pointer moves.
        let leadingMinimum = min(leadingStart, max(0, minimumWidths[leading] ?? 0))
        let trailingMinimum = min(trailingStart, max(0, minimumWidths[trailing] ?? 0))
        let lowerDelta = leadingMinimum - leadingStart
        let upperDelta = trailingStart - trailingMinimum
        let clampedDelta = min(upperDelta, max(lowerDelta, delta))
        return [
            leading: leadingStart + clampedDelta,
            trailing: trailingStart - clampedDelta,
        ]
    }
}

struct HolyLedgerColumnFrame: Equatable, Sendable {
    let minX: CGFloat
    let width: CGFloat
}

struct HolyLedgerColumnDragSnapshot: Equatable, Sendable {
    let widths: [String: CGFloat]
    let frames: [String: HolyLedgerColumnFrame]
    let availableWidth: CGFloat
}

/// One physical divider drag. All geometry and bounds are captured at gesture
/// start. Intermediate pointer events only update an in-memory pixel snapshot;
/// the caller receives one normalized persistence value when the gesture ends.
struct HolyLedgerColumnDragSession: Equatable, Sendable {
    static let writeEpsilon: CGFloat = 0.5

    private let boundary: HolyLedgerColumnBoundary
    private let startingWidths: [String: CGFloat]
    private let minimumWidths: [String: CGFloat]
    private let columnOrder: [String]
    private let columnGap: CGFloat
    private let startingPointerX: CGFloat
    private let availableWidth: CGFloat
    private(set) var currentWidths: [String: CGFloat]
    private(set) var hasFinished = false

    init(
        boundary: HolyLedgerColumnBoundary,
        startingWidths: [String: CGFloat],
        minimumWidths: [String: CGFloat],
        columnOrder: [String],
        columnGap: CGFloat,
        startingPointerX: CGFloat,
        availableWidth: CGFloat
    ) {
        let leadingIndex = columnOrder.firstIndex(of: boundary.leading)
        let trailingIndex = columnOrder.firstIndex(of: boundary.trailing)
        precondition(
            leadingIndex != nil && trailingIndex == leadingIndex.map { $0 + 1 },
            "A ledger grip must join adjacent columns"
        )
        self.boundary = boundary
        self.startingWidths = startingWidths
        self.minimumWidths = minimumWidths
        self.columnOrder = columnOrder
        self.columnGap = columnGap
        self.startingPointerX = startingPointerX
        self.availableWidth = availableWidth
        currentWidths = startingWidths
    }

    mutating func update(pointerX: CGFloat) -> HolyLedgerColumnDragSnapshot? {
        guard !hasFinished else { return nil }
        let resized = boundary.resizedWidths(
            from: startingWidths,
            minimumWidths: minimumWidths,
            translation: pointerX - startingPointerX
        )
        var next = startingWidths
        for (column, width) in resized {
            next[column] = width
        }
        guard Self.differs(next, from: currentWidths) else { return nil }
        currentWidths = next
        return snapshot
    }

    mutating func finish(pointerX: CGFloat) -> HolyLedgerColumnDragSnapshot? {
        guard !hasFinished else { return nil }
        _ = update(pointerX: pointerX)
        hasFinished = true
        return Self.differs(currentWidths, from: startingWidths) ? snapshot : nil
    }

    private var snapshot: HolyLedgerColumnDragSnapshot {
        .init(
            widths: currentWidths,
            frames: Self.frames(columnOrder: columnOrder, widths: currentWidths, gap: columnGap),
            availableWidth: availableWidth
        )
    }

    static func frames(
        columnOrder: [String],
        widths: [String: CGFloat],
        gap: CGFloat
    ) -> [String: HolyLedgerColumnFrame] {
        var minX: CGFloat = 0
        return columnOrder.reduce(into: [:]) { frames, column in
            let width = widths[column] ?? 0
            frames[column] = .init(minX: minX, width: width)
            minX += width + gap
        }
    }

    private static func differs(
        _ left: [String: CGFloat],
        from right: [String: CGFloat]
    ) -> Bool {
        Set(left.keys).union(right.keys).contains { column in
            abs((left[column] ?? 0) - (right[column] ?? 0)) >= writeEpsilon
        }
    }
}

/// Inspector resizing follows the same transaction law as a column boundary:
/// a static range and origin for the whole gesture, previews in memory, and
/// exactly one persisted width on end.
struct HolyLedgerInspectorDragSession: Equatable, Sendable {
    static let writeEpsilon: CGFloat = 0.5

    private let startingWidth: CGFloat
    private let bounds: ClosedRange<CGFloat>
    private let startingPointerX: CGFloat
    private(set) var currentWidth: CGFloat
    private(set) var hasFinished = false

    init(
        startingWidth: CGFloat,
        bounds: ClosedRange<CGFloat>,
        startingPointerX: CGFloat
    ) {
        self.startingWidth = startingWidth
        self.bounds = bounds
        self.startingPointerX = startingPointerX
        currentWidth = min(bounds.upperBound, max(bounds.lowerBound, startingWidth))
    }

    mutating func update(pointerX: CGFloat) -> CGFloat? {
        guard !hasFinished else { return nil }
        let proposed = (startingWidth - (pointerX - startingPointerX)).rounded()
        let next = min(bounds.upperBound, max(bounds.lowerBound, proposed))
        guard abs(next - currentWidth) >= Self.writeEpsilon else { return nil }
        currentWidth = next
        return next
    }

    mutating func finish(pointerX: CGFloat) -> CGFloat? {
        guard !hasFinished else { return nil }
        _ = update(pointerX: pointerX)
        hasFinished = true
        return abs(currentWidth - startingWidth) >= Self.writeEpsilon ? currentWidth : nil
    }
}

/// Canonical physical grip positions for the two native ledgers. Tests use
/// this same map, so adding or reordering a fixed column cannot silently bring
/// back the reversed-control bug.
enum HolyLedgerColumnBoundaries {
    static func boardOrder(showsTrack: Bool) -> [String] {
        showsTrack
            ? ["id", "digest", "track", "state", "#"]
            : ["id", "digest", "state", "#"]
    }

    static func board(column: String, showsTrack: Bool) -> HolyLedgerColumnBoundary {
        switch column {
        case "id": return .init(leading: "id", trailing: "digest", gripOnLeadingEdge: false)
        case "track": return .init(leading: "digest", trailing: "track", gripOnLeadingEdge: true)
        case "state":
            let leading = showsTrack ? "track" : "digest"
            return .init(leading: leading, trailing: "state", gripOnLeadingEdge: true)
        case "#": return .init(leading: "state", trailing: "#", gripOnLeadingEdge: true)
        default: preconditionFailure("Unknown Board column: \(column)")
        }
    }

    static func archiveOrder(showsProject: Bool) -> [String] {
        showsProject
            ? ["date", "harness", "project", "summary", "sub"]
            : ["date", "harness", "summary", "sub"]
    }

    static func archive(column: String, showsProject: Bool) -> HolyLedgerColumnBoundary {
        switch column {
        case "date": return .init(leading: "date", trailing: "harness", gripOnLeadingEdge: false)
        case "harness":
            let trailing = showsProject ? "project" : "summary"
            return .init(leading: "harness", trailing: trailing, gripOnLeadingEdge: false)
        case "project": return .init(leading: "project", trailing: "summary", gripOnLeadingEdge: false)
        case "sub": return .init(leading: "summary", trailing: "sub", gripOnLeadingEdge: true)
        default: preconditionFailure("Unknown Archive column: \(column)")
        }
    }
}

/// The 9px-wide drag zone on a physical column boundary (styles.css
/// `.cols .grip`), drawn as a 1px rule that brightens under the pointer.
struct HolyLedgerColumnGrip: View {
    static let width: CGFloat = 9
    /// A column never shrinks under its header label (app.js: the label is
    /// the fit floor).
    static let minimumCharacters = 2

    let boundary: HolyLedgerColumnBoundary
    let currentWidths: [String: CGFloat]
    let minimumWidths: [String: CGFloat]
    let columnOrder: [String]
    let columnGap: CGFloat
    let availableWidth: CGFloat
    let onPreview: (HolyLedgerColumnDragSnapshot) -> Void
    let onCommit: (HolyLedgerColumnDragSnapshot) -> Void
    let onEnd: () -> Void
    let onReset: ([String]) -> Void

    @State private var dragSession: HolyLedgerColumnDragSession?
    @State private var hovered = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: Self.width)
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(hovered || dragSession != nil ? HolyMannaBoardPalette.lineStrong : HolyMannaBoardPalette.line)
                    .frame(width: hovered || dragSession != nil ? 2 : 1, height: 18)
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        var session = dragSession ?? HolyLedgerColumnDragSession(
                            boundary: boundary,
                            startingWidths: currentWidths,
                            minimumWidths: minimumWidths,
                            columnOrder: columnOrder,
                            columnGap: columnGap,
                            startingPointerX: value.startLocation.x,
                            availableWidth: availableWidth
                        )
                        if let preview = session.update(pointerX: value.location.x) {
                            dragSession = session
                            onPreview(preview)
                        } else if dragSession == nil {
                            dragSession = session
                        }
                    }
                    .onEnded { value in
                        guard var session = dragSession else {
                            onEnd()
                            return
                        }
                        if let commit = session.finish(pointerX: value.location.x) {
                            onCommit(commit)
                        }
                        dragSession = nil
                        onEnd()
                    }
            )
            .onTapGesture(count: 2) { onReset(boundary.columns) }
            .help("drag · double-click to refit")
    }
}
