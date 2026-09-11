#if os(macOS)
import AppKit
import CoreText
import GhosttyKit
import SwiftUI

/// The embedded API has no content-revision callback. Poll only presented
/// panes, using one bounded viewport read per sample. Resolve cell prefixes
/// only once output has settled, and verify the sample again before painting.
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

    @Published private(set) var frame: Frame?
    private var stability = HolyMannaLink.ViewportStability()
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
        stability.invalidate()
        if frame != nil { frame = nil }
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
        defer { invalidate() }
        while !Task.isCancelled {
            sample(view)
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
    }

    private func read(_ surface: ghostty_surface_t, through cell: Int, columns: Int) -> ghostty_text_s? {
        var text = ghostty_text_s()
        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT,
                                         x: UInt32(cell % columns), y: UInt32(cell / columns)),
            rectangle: false)
        return ghostty_surface_read_text(surface, selection, &text) ? text : nil
    }

    private func snapshot(_ view: Ghostty.SurfaceView, surface: ghostty_surface_t) -> HolyMannaLink.Viewport? {
        let size = ghostty_surface_size(surface)
        let columns = Int(size.columns)
        let rows = Int(size.rows)
        guard columns > 0, rows > 0, size.cell_width_px > 0, size.cell_height_px > 0,
              var text = read(surface, through: columns * rows - 1, columns: columns) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard text.tl_px_x >= 0, text.tl_px_y >= 0, text.offset_start == 0 else { return nil }
        let cellSize = view.convertFromBacking(CGSize(width: CGFloat(size.cell_width_px), height: CGFloat(size.cell_height_px)))
        var imeX = 0.0, imeY = 0.0, imeWidth = 0.0, imeHeight = 0.0
        ghostty_surface_ime_point(surface, &imeX, &imeY, &imeWidth, &imeHeight)
        let baseline = CGPoint(x: text.tl_px_x, y: text.tl_px_y)
        guard abs(imeHeight - cellSize.height) < 0.01,
              let origin = HolyMannaLink.gridOrigin(baseline: baseline, imeCellBottom: imeY,
                                                     cellHeight: cellSize.height) else { return nil }
        return .init(text: String(cString: text.text), columns: columns, rows: rows,
                     baseline: baseline, gridOrigin: origin, cellSize: cellSize)
    }

    private func sample(_ view: Ghostty.SurfaceView) {
        guard view.window?.occlusionState.contains(.visible) == true, !view.isHiddenOrHasHiddenAncestor,
              let surface = view.surface, !ghostty_surface_has_selection(surface),
              let viewport = snapshot(view, surface: surface) else {
            invalidate()
            return
        }
        switch stability.observe(viewport) {
        case .clear:
            if frame != nil { frame = nil }
            return
        case .keep:
            return
        case .paint:
            break
        }
        guard let blue = blueOverride ?? view.derivedConfig.mannaLinkBlue,
              let fontRaw = ghostty_surface_quicklook_font(surface) else { return }
        let font = Unmanaged<CTFont>.fromOpaque(fontRaw).takeRetainedValue()
        let runs = HolyMannaLink.paintRuns(in: viewport) { cell in
            guard var text = self.read(surface, through: cell, columns: viewport.columns) else { return nil }
            defer { ghostty_surface_free_text(surface, &text) }
            return String(cString: text.text)
        }
        guard let runs, snapshot(view, surface: surface) == viewport else {
            invalidate()
            return
        }
        var glyphRuns: [GlyphRun] = []
        for run in runs {
            let characters = Array(run.text.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            guard CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count) else {
                invalidate()
                return
            }
            glyphRuns.append(.init(cells: run, glyphs: glyphs))
        }
        stability.didPaint()
        guard !glyphRuns.isEmpty else { frame = nil; return }
        frame = Frame(runs: glyphRuns, font: font, blue: blue.withAlphaComponent(1).cgColor,
                      background: NSColor(view.backgroundColor ?? view.derivedConfig.backgroundColor).withAlphaComponent(1).cgColor,
                      cellWidth: viewport.cellSize.width)
    }
}

struct HolyMannaLinkOverlay: View {
    let surfaceView: Ghostty.SurfaceView
    @ObservedObject var painter: HolyMannaLinkPainter

    var body: some View {
        Canvas { context, size in
            guard let frame = painter.frame else { return }
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
