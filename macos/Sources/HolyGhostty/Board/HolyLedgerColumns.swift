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
    let flexibleWidth: CGFloat
    let chromeWidth: CGFloat
    let discardedStoredWidths: Bool
    private let widths: [String: CGFloat]

    init(
        availableWidth: CGFloat,
        flexibleWidth: CGFloat,
        chromeWidth: CGFloat,
        discardedStoredWidths: Bool,
        widths: [String: CGFloat]
    ) {
        self.availableWidth = availableWidth
        self.flexibleWidth = flexibleWidth
        self.chromeWidth = chromeWidth
        self.discardedStoredWidths = discardedStoredWidths
        self.widths = widths
    }

    func width(_ column: String, fallback: CGFloat = 0) -> CGFloat {
        widths[column] ?? fallback
    }

    func widths(for columns: [String]) -> [String: CGFloat] {
        columns.reduce(into: [:]) { result, column in
            result[column] = widths[column]
        }
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
        let persisted = min(maximumWidth, max(minimumWidth, persistedWidth))
        let proportionalCap = max(0, windowWidth * inspectorFraction)
        let breakpointCap = windowWidth <= HolyMannaBoardMetrics.narrowBreakpoint
            ? narrowWidth
            : maximumWidth
        let cap = min(maximumWidth, min(proportionalCap, breakpointCap))
        return max(minimumWidth, min(persisted, cap))
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
        overrides: HolyLedgerColumnOverrides
    ) -> HolyLedgerResolvedColumns {
        let available = max(0, availableWidth)
        let chrome = stripeWidth + CGFloat(fixedColumns.count + 1) * gap
        let requestedFlexible = min(minimumFlexibleWidth, max(0, available - chrome))
        let fixedBudget = max(0, available - chrome - requestedFlexible)
        var widths = fixedColumns.reduce(into: [String: CGFloat]()) { result, column in
            let preferred = overrides.width(
                column.id,
                fitted: column.fittedWidth,
                availableWidth: available
            )
            result[column.id] = max(column.minimumWidth, preferred)
        }

        let usesStoredWidths = fixedColumns.contains { overrides.hasOverride($0.id) }
        let storedWidthsStarveFlex = usesStoredWidths && widths.values.reduce(0, +) > fixedBudget
        if storedWidthsStarveFlex {
            widths = fixedColumns.reduce(into: [:]) { result, column in
                result[column.id] = max(column.minimumWidth, column.fittedWidth)
            }
        }

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
            flexibleWidth: flexible,
            chromeWidth: chrome,
            discardedStoredWidths: storedWidthsStarveFlex,
            widths: widths
        )
    }
}

/// The fixed columns touching one physical divider. The flexible column is
/// implicit: left-side grips resize the fixed column before it, the first
/// right-side grip resizes the fixed column after it with reversed delta, and
/// later right-side grips transfer the same width between neighboring fixed
/// columns. In every case the divider follows the pointer.
enum HolyLedgerColumnBoundary: Equatable, Sendable {
    case fixedBeforeFlexible(String)
    case fixedAfterFlexible(String)
    case fixedPair(leading: String, trailing: String)

    var columns: [String] {
        switch self {
        case let .fixedBeforeFlexible(column), let .fixedAfterFlexible(column):
            [column]
        case let .fixedPair(leading, trailing):
            [leading, trailing]
        }
    }

    var gripOnLeadingEdge: Bool {
        switch self {
        case .fixedBeforeFlexible: false
        case .fixedAfterFlexible, .fixedPair: true
        }
    }

    func resizedWidths(
        from startingWidths: [String: CGFloat],
        minimumWidths: [String: CGFloat],
        translation: CGFloat
    ) -> [String: CGFloat] {
        let delta = translation.rounded()
        switch self {
        case let .fixedBeforeFlexible(column):
            let start = startingWidths[column] ?? 0
            return [column: max(minimumWidths[column] ?? 0, start + delta)]
        case let .fixedAfterFlexible(column):
            let start = startingWidths[column] ?? 0
            return [column: max(minimumWidths[column] ?? 0, start - delta)]
        case let .fixedPair(leading, trailing):
            let leadingStart = startingWidths[leading] ?? 0
            let trailingStart = startingWidths[trailing] ?? 0
            let lowerDelta = (minimumWidths[leading] ?? 0) - leadingStart
            let upperDelta = trailingStart - (minimumWidths[trailing] ?? 0)
            let clampedDelta = min(upperDelta, max(lowerDelta, delta))
            return [
                leading: leadingStart + clampedDelta,
                trailing: trailingStart - clampedDelta,
            ]
        }
    }
}

/// Canonical physical grip positions for the two native ledgers. Tests use
/// this same map, so adding or reordering a fixed column cannot silently bring
/// back the reversed-control bug.
enum HolyLedgerColumnBoundaries {
    static func board(column: String, showsTrack: Bool) -> HolyLedgerColumnBoundary {
        switch column {
        case "id": return .fixedBeforeFlexible("id")
        case "track": return .fixedAfterFlexible("track")
        case "state":
            if showsTrack {
                return .fixedPair(leading: "track", trailing: "state")
            }
            return .fixedAfterFlexible("state")
        case "#": return .fixedPair(leading: "state", trailing: "#")
        default: preconditionFailure("Unknown Board column: \(column)")
        }
    }

    static func archive(column: String) -> HolyLedgerColumnBoundary {
        switch column {
        case "date", "harness", "project": return .fixedBeforeFlexible(column)
        case "sub": return .fixedAfterFlexible("sub")
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
    let onResize: ([String: CGFloat]) -> Void
    let onReset: ([String]) -> Void

    @State private var dragStartWidths: [String: CGFloat]?
    @State private var hovered = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: Self.width)
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(hovered || dragStartWidths != nil ? HolyMannaBoardPalette.lineStrong : HolyMannaBoardPalette.line)
                    .frame(width: hovered || dragStartWidths != nil ? 2 : 1, height: 18)
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartWidths ?? currentWidths
                        dragStartWidths = start
                        onResize(boundary.resizedWidths(
                            from: start,
                            minimumWidths: minimumWidths,
                            translation: value.translation.width
                        ))
                    }
                    .onEnded { _ in dragStartWidths = nil }
            )
            .onTapGesture(count: 2) { onReset(boundary.columns) }
            .help("drag · double-click to refit")
    }
}
