import Foundation
import SwiftUI

/// app.js grips: every fixed column of a ledger is fitted to its widest
/// cell, and the user may drag its right edge (stored per column, per
/// face) and double-click the grip to return to the fit.
struct HolyLedgerColumnOverrides: Equatable {
    private(set) var widths: [String: CGFloat] = [:]

    init(json: String) {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else { return }
        widths = decoded.mapValues { CGFloat($0) }
    }

    var json: String {
        let data = (try? JSONEncoder().encode(widths.mapValues(Double.init))) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// The fitted width unless the user dragged this column.
    func width(_ column: String, fitted: CGFloat) -> CGFloat {
        widths[column] ?? fitted
    }

    mutating func set(_ column: String, width: CGFloat) {
        widths[column] = width
    }

    mutating func reset(_ column: String) {
        widths[column] = nil
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
