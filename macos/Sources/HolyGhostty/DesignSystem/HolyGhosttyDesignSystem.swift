import AppKit
import SwiftUI

// MARK: - Theme

enum HolyGhosttyTheme {

    // MARK: Backgrounds (neutral darks, tight range)
    static let bg = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let bgElevated = Color(red: 0.07, green: 0.07, blue: 0.09)
    static let bgSurface = Color(red: 0.10, green: 0.10, blue: 0.12)

    // MARK: Halo — primary brand accent (logo's golden halo)
    static let halo = Color(red: 0.88, green: 0.75, blue: 0.35)

    // MARK: Accent — informational blue (calmer than old cyan)
    static let accent = Color(red: 0.45, green: 0.65, blue: 0.82)
    static let accentSoft = Color(red: 0.40, green: 0.48, blue: 0.58)

    // MARK: Semantic
    static let success = Color(red: 0.35, green: 0.75, blue: 0.52)
    static let warning = Color(red: 0.92, green: 0.68, blue: 0.28)
    static let danger = Color(red: 0.92, green: 0.38, blue: 0.38)

    // MARK: Text hierarchy
    static let textPrimary = Color.white.opacity(0.88)
    static let textSecondary = Color.white.opacity(0.48)
    static let textTertiary = Color.white.opacity(0.28)

    // MARK: Borders
    static let border = Color.white.opacity(0.05)
    static let borderActive = Color.white.opacity(0.10)

    // MARK: Legacy aliases
    static let backgroundTop = bg
    static let backgroundBottom = bg
    static let panel = bgElevated
    static let panelElevated = bgSurface
    static let mutedBorder = Color.white.opacity(0.03)
    static let mutedText = textSecondary
}

// MARK: - Backdrop

struct HolyGhosttyBackdrop: View {
    var body: some View {
        HolyGhosttyTheme.bg
            .ignoresSafeArea()
    }
}

// MARK: - Panel (minimal container — just padding, no chrome)

struct HolyGhosttyPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(10)
    }
}

// MARK: - Empty State

struct HolyGhosttyEmptyStateView: View {
    let title: String
    let subtitle: String
    var symbol: String = "rectangle.stack.badge.minus"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HolyGhosttyTheme.textSecondary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(HolyGhosttyTheme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

// MARK: - Surface Frame (with halo glow — the signature move)

struct HolyGhosttySurfaceFrame<Content: View>: View {
    let title: String?
    let halo: Bool
    let content: Content

    init(title: String? = nil, halo: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.halo = halo
        self.content = content()
    }

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        halo ? HolyGhosttyTheme.halo.opacity(0.28) : HolyGhosttyTheme.border,
                        lineWidth: halo ? 1 : 0.5
                    )
            )
            .shadow(color: halo ? HolyGhosttyTheme.halo.opacity(0.15) : .clear, radius: 16, x: 0, y: 0)
            .shadow(color: halo ? HolyGhosttyTheme.halo.opacity(0.08) : .clear, radius: 36, x: 0, y: 2)
    }
}

// MARK: - Section Header (single quiet label)

struct HolyGhosttySectionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String?

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(HolyGhosttyTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

// MARK: - Stat Pill (reduced to inline text — no container)

struct HolyGhosttyStatPill: View {
    let label: String
    let value: String
    var tint: Color = HolyGhosttyTheme.textSecondary

    var body: some View {
        Text(value)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

// MARK: - Status Dot (smaller, no glow)

struct HolyGhosttyStatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }
}

// MARK: - Action Button (tighter, more native)

struct HolyGhosttyActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? HolyGhosttyTheme.bgSurface : HolyGhosttyTheme.bgElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(HolyGhosttyTheme.border, lineWidth: 0.5)
            )
            .foregroundStyle(HolyGhosttyTheme.textPrimary)
    }
}
