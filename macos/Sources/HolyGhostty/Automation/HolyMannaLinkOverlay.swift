#if os(macOS)
import AppKit
import CoreText
import GhosttyKit
import SwiftUI

/// The embedded API has no content-revision callback. Poll only presented
/// panes, retaining each accepted row while other rows stream or animate.
@MainActor
final class HolyMannaLinkPainter: ObservableObject {
    struct GlyphRun {
        let cells: HolyMannaLink.PaintRun
        let glyphs: [CGGlyph]
    }

    struct Frame {
        let runs: [GlyphRun]
        let font: CTFont
        let blue: CGColor
        let background: CGColor
        let cellWidth: CGFloat
    }

    struct Style {
        let font: CTFont
        let blue: NSColor
        let background: NSColor
    }

    @Published private(set) var frame: Frame?
    @Published private(set) var isSelecting = false
    private var rows = HolyMannaLink.RowPaintState()
    private var viewport: HolyMannaLink.Viewport?
    private var blueOverride: NSColor?

    nonisolated static func paletteBlue(_ config: Ghostty.Config) -> NSColor? {
        guard let config = config.config else { return nil }
        var palette = ghostty_config_palette_s()
        guard ghostty_config_get(config, &palette, "palette", 7) else { return nil }
        let blue = palette.colors.4
        return NSColor(srgbRed: CGFloat(blue.r) / 255, green: CGFloat(blue.g) / 255,
                       blue: CGFloat(blue.b) / 255, alpha: 1)
    }

    func invalidate() {
        rows.invalidate()
        viewport = nil
        if frame != nil { frame = nil }
    }

    func scrollbarChanged(from old: Ghostty.Action.Scrollbar?, to new: Ghostty.Action.Scrollbar?) {
        // Growing history below an unchanged viewport does not move its rows.
        if old?.offset != new?.offset || old?.len != new?.len { invalidate() }
    }

    func configChanged() {
        blueOverride = nil
        invalidate()
    }

    func paletteChanged(_ color: Color) {
        blueOverride = NSColor(color)
        invalidate()
    }

    func watch(_ view: Ghostty.SurfaceView) async {
        while !Task.isCancelled {
            sample(view)
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
    }

    private func read(_ surface: ghostty_surface_t, cells: ClosedRange<Int>, columns: Int) -> ghostty_text_s? {
        var text = ghostty_text_s()
        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT,
                                     x: UInt32(cells.lowerBound % columns), y: UInt32(cells.lowerBound / columns)),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT,
                                         x: UInt32(cells.upperBound % columns), y: UInt32(cells.upperBound / columns)),
            // A single physical row must not expand a trailing wide spacer
            // into the next row. Multirow reads retain core soft-wrap joins.
            rectangle: cells.lowerBound / columns == cells.upperBound / columns)
        return ghostty_surface_read_text(surface, selection, &text) ? text : nil
    }

    private func snapshot(_ surface: ghostty_surface_t) -> HolyMannaLink.Viewport? {
        let size = ghostty_surface_size(surface)
        let columns = Int(size.columns)
        let rows = Int(size.rows)
        guard columns > 0, rows > 0, size.cell_width_px > 0, size.cell_height_px > 0,
              var text = read(surface, cells: 0...0, columns: columns) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard text.tl_px_x >= 0, text.tl_px_y >= 0, text.offset_start == 0 else { return nil }
        var nextColumnX: CGFloat?
        if columns > 1 {
            guard var next = read(surface, cells: 1...1, columns: columns) else { return nil }
            defer { ghostty_surface_free_text(surface, &next) }
            guard next.offset_start == 1 else { return nil }
            nextColumnX = next.tl_px_x
        }
        var imeX = 0.0, imeY = 0.0, imeWidth = 0.0, imeHeight = 0.0
        ghostty_surface_ime_point(surface, &imeX, &imeY, &imeWidth, &imeHeight)
        let baseline = CGPoint(x: text.tl_px_x, y: text.tl_px_y)
        // Keep cell size, baseline, and IME anchor in the same core coordinate
        // system, even while AppKit's backing scale is changing.
        return HolyMannaLink.viewport(columns: columns, rows: rows, baseline: baseline, nextColumnX: nextColumnX,
                                      imeAnchor: CGPoint(x: imeX, y: imeY), cellHeight: imeHeight)
    }

    private func sample(_ view: Ghostty.SurfaceView) {
        guard view.window?.occlusionState.contains(.visible) == true, !view.isHiddenOrHasHiddenAncestor,
              let surface = view.surface else { return }
        let selecting = ghostty_surface_has_selection(surface)
        if isSelecting != selecting { isSelecting = selecting }
        guard !selecting, let viewport = snapshot(surface) else { return }
        sample(viewport: viewport, readCells: { cells in
            guard var text = self.read(surface, cells: cells, columns: viewport.columns) else { return nil }
            defer { ghostty_surface_free_text(surface, &text) }
            return String(cString: text.text)
        }, style: {
            guard let blue = self.blueOverride ?? view.derivedConfig.mannaLinkBlue,
                  let fontRaw = ghostty_surface_quicklook_font(surface) else { return nil }
            return Style(font: Unmanaged<CTFont>.fromOpaque(fontRaw).takeRetainedValue(), blue: blue,
                         background: NSColor(view.backgroundColor ?? view.derivedConfig.backgroundColor))
        })
    }

    /// Shared by the surface adapter and deterministic hosted regressions.
    /// Transient row changes never publish an empty intermediate frame.
    func sample(viewport: HolyMannaLink.Viewport, readCells: (ClosedRange<Int>) -> String?, style: () -> Style?) {
        if self.viewport != viewport {
            invalidate()
            self.viewport = viewport
        }
        let runs = rows.sample(viewport, readCells: readCells)
        guard runs != (frame?.runs.map(\.cells) ?? []), let style = style() else { return }
        var glyphRuns: [GlyphRun] = []
        for run in runs {
            let characters = Array(run.text.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            guard CTFontGetGlyphsForCharacters(style.font, characters, &glyphs, characters.count) else { return }
            glyphRuns.append(.init(cells: run, glyphs: glyphs))
        }
        frame = Frame(runs: glyphRuns, font: style.font, blue: style.blue.withAlphaComponent(1).cgColor,
                      background: style.background.withAlphaComponent(1).cgColor,
                      cellWidth: viewport.cellSize.width)
    }
}

struct HolyMannaLinkOverlay: View {
    let surfaceView: Ghostty.SurfaceView
    @ObservedObject var painter: HolyMannaLinkPainter

    var body: some View {
        Canvas { context, size in
            guard !painter.isSelecting, let frame = painter.frame else { return }
            context.withCGContext { graphics in
                graphics.setFillColor(frame.background)
                // Erase the original glyphs before drawing any replacements.
                for run in frame.runs { graphics.fill(run.cells.rect) }
                graphics.translateBy(x: 0, y: size.height)
                graphics.scaleBy(x: 1, y: -1)
                graphics.textMatrix = .identity
                graphics.setFillColor(frame.blue)
                for run in frame.runs {
                    let positions = run.glyphs.indices.map {
                        CGPoint(x: run.cells.baseline.x + CGFloat($0) * frame.cellWidth,
                                y: size.height - run.cells.baseline.y)
                    }
                    CTFontDrawGlyphs(frame.font, run.glyphs, positions, run.glyphs.count, graphics)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task { await painter.watch(surfaceView) }
    }
}
#endif
