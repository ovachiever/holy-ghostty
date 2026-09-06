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
    let shrinkPriority: Int
}

struct HolyLedgerResolvedColumns: Equatable, Sendable {
    let availableWidth: CGFloat
    let flexibleWidth: CGFloat
    let chromeWidth: CGFloat
    private let widths: [String: CGFloat]

    init(
        availableWidth: CGFloat,
        flexibleWidth: CGFloat,
        chromeWidth: CGFloat,
        widths: [String: CGFloat]
    ) {
        self.availableWidth = availableWidth
        self.flexibleWidth = flexibleWidth
        self.chromeWidth = chromeWidth
        self.widths = widths
    }

    func width(_ column: String, fallback: CGFloat = 0) -> CGFloat {
        widths[column] ?? fallback
    }

    var occupiedWidth: CGFloat {
        chromeWidth + flexibleWidth + widths.values.reduce(0, +)
    }
}

/// One responsive law for the Board and Archive ledgers. The flexible text
/// column receives its readable floor first. Dragged fixed widths then fit
/// inside what remains, shrinking toward their semantic floors in priority
/// order. GeometryReader supplies the current window width, so a resize or
/// screen move recomputes the result without mutating the stored preference.
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

        var deficit = max(0, widths.values.reduce(0, +) - fixedBudget)
        let shrinkOrder = fixedColumns.enumerated().sorted { left, right in
            if left.element.shrinkPriority != right.element.shrinkPriority {
                return left.element.shrinkPriority < right.element.shrinkPriority
            }
            return left.offset < right.offset
        }
        for entry in shrinkOrder where deficit > 0 {
            let column = entry.element
            let current = widths[column.id] ?? 0
            let reduction = min(deficit, max(0, current - column.minimumWidth))
            widths[column.id] = current - reduction
            deficit -= reduction
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
            widths: widths
        )
    }
}

/// The 9px-wide drag zone at a column header's right edge (styles.css
/// `.cols .grip`), drawn as a 1px rule that brightens under the pointer.
struct HolyLedgerColumnGrip: View {
    static let width: CGFloat = 9
    /// A column never shrinks under its header label (app.js: the label is
    /// the fit floor).
    static let minimumCharacters = 2

    let column: String
    let currentWidth: CGFloat
    let minimumWidth: CGFloat
    let onResize: (CGFloat) -> Void
    let onReset: () -> Void

    @State private var dragStartWidth: CGFloat?
    @State private var hovered = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: Self.width)
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(hovered || dragStartWidth != nil ? HolyMannaBoardPalette.lineStrong : HolyMannaBoardPalette.line)
                    .frame(width: hovered || dragStartWidth != nil ? 2 : 1, height: 18)
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartWidth ?? currentWidth
                        dragStartWidth = start
                        onResize(max(minimumWidth, (start + value.translation.width).rounded()))
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
            .onTapGesture(count: 2, perform: onReset)
            .help("drag · double-click to refit")
    }
}
