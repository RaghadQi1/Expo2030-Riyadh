import SwiftUI

/// Spacing / radius tokens observed in the Figma file.
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    /// Horizontal screen margin used on every screen (16pt).
    static let screen: CGFloat = 16
}

enum Radius {
    static let chip: CGFloat = 999
    static let small: CGFloat = 10
    static let field: CGFloat = 14
    static let row: CGFloat = 18
    static let button: CGFloat = 16
    static let card: CGFloat = 24
    static let sheet: CGFloat = 28
}

extension View {
    /// Figma "Shadow/Card": two very soft drop shadows (#0A1F17 @ 2%).
    func cardShadow() -> some View {
        shadow(color: .shadowTint.opacity(0.02), radius: 4, x: 0, y: 2)
            .shadow(color: .shadowTint.opacity(0.02), radius: 12, x: 0, y: 8)
    }

    /// Figma "Glass/Light" drop shadow (#0A1F17 @ 10%, y 8, blur 24).
    func glassShadow() -> some View {
        shadow(color: .shadowTint.opacity(0.10), radius: 12, x: 0, y: 8)
    }

    /// Floating glass surface (background blur + tint + 1pt white stroke) used by map controls,
    /// the tab bar and floating sheets.
    func glassBackground<S: InsettableShape>(_ shape: S, tint: Color = .glassTintStrong, stroke: Color = .glassStroke) -> some View {
        background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(tint)
            }
        }
        .overlay(shape.strokeBorder(stroke, lineWidth: 1))
    }

    func cardBackground(radius: CGFloat = Radius.card, color: Color = .bgSurface) -> some View {
        background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .cardShadow()
    }
}
