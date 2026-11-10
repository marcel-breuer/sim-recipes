import SwiftUI
import UIKit

/// The shared glass design: translucent, blurred surfaces with a bright
/// specular edge and rim, tinted with the app's blue accent (system blue).
/// All values live in `Glass`; views only use the modifiers below.
enum Glass {
    // Radius scale.
    static let panelRadius: CGFloat = 20   // panels, menus, cards
    static let insetRadius: CGFloat = 16   // nested insets
    static let sheetRadius: CGFloat = 24   // dialogs and sheets
    static let controlRadius: CGFloat = 10 // small controls

    /// Inner radius = outer radius minus padding, never below 4.
    static func innerRadius(outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(4, outer - padding)
    }

    // Brand blue (system accent) shades the color field and shadow derive from.
    private static let blue300 = UIColor(red: 0.49, green: 0.71, blue: 1.00, alpha: 1)
    private static let blue200 = UIColor(red: 0.65, green: 0.80, blue: 1.00, alpha: 1)
    private static let blue400 = UIColor(red: 0.30, green: 0.57, blue: 0.98, alpha: 1)
    private static let blue900 = UIColor(red: 0.04, green: 0.14, blue: 0.40, alpha: 1)
    private static let blue800 = UIColor(red: 0.07, green: 0.22, blue: 0.56, alpha: 1)
    private static let blue700 = UIColor(red: 0.10, green: 0.31, blue: 0.72, alpha: 1)
    private static let blue600 = UIColor(red: 0.12, green: 0.40, blue: 0.88, alpha: 1)

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    // Solid fallback surfaces (reduced transparency, increased contrast).
    static let solid = dynamic(
        light: UIColor(red: 0.98, green: 0.99, blue: 1.00, alpha: 1),
        dark: UIColor(red: 0.09, green: 0.11, blue: 0.16, alpha: 1))
    static let solidInset = dynamic(
        light: UIColor(red: 0.94, green: 0.96, blue: 0.99, alpha: 1),
        dark: UIColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1))
    static let solidBorder = dynamic(
        light: UIColor(red: 0.78, green: 0.84, blue: 0.93, alpha: 1),
        dark: UIColor(red: 0.26, green: 0.31, blue: 0.40, alpha: 1))

    // Translucent fills. The system material supplies the blur and saturation.
    static let fill = dynamic(
        light: UIColor(red: 0.98, green: 0.99, blue: 1.00, alpha: 0.52),
        dark: UIColor.white.withAlphaComponent(0.07))
    static let insetFill = dynamic(
        light: UIColor(red: 0.98, green: 0.99, blue: 1.00, alpha: 0.38),
        dark: UIColor.white.withAlphaComponent(0.05))

    static let edge = dynamic(
        light: UIColor.white.withAlphaComponent(0.90),
        dark: UIColor.white.withAlphaComponent(0.22))
    static let rim = dynamic(
        light: UIColor.white.withAlphaComponent(0.50),
        dark: UIColor.white.withAlphaComponent(0.08))
    static let shadow = dynamic(
        light: blue900.withAlphaComponent(0.10),
        dark: UIColor.black.withAlphaComponent(0.35))

    // Backdrop field: soft blobs of the brand blue, deeper shades in dark.
    static let blobA = dynamic(light: blue300.withAlphaComponent(0.38), dark: blue700.withAlphaComponent(0.42))
    static let blobB = dynamic(light: blue200.withAlphaComponent(0.46), dark: blue800.withAlphaComponent(0.46))
    static let blobC = dynamic(light: blue400.withAlphaComponent(0.26), dark: blue600.withAlphaComponent(0.26))
    static let backdropBase = dynamic(
        light: UIColor(red: 0.95, green: 0.97, blue: 1.00, alpha: 1),
        dark: UIColor(red: 0.04, green: 0.06, blue: 0.10, alpha: 1))

    enum Level { case panel, inset }
}

/// A large, fixed color field the glass can blur. No pattern, no animation.
struct GlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            Glass.backdropBase

            if !reduceTransparency && contrast == .standard {
                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    ZStack {
                        blob(Glass.blobA, size: w * 1.1).position(x: w * 0.12, y: h * 0.08)
                        blob(Glass.blobB, size: w * 1.0).position(x: w * 0.92, y: h * 0.30)
                        blob(Glass.blobC, size: w * 1.1).position(x: w * 0.30, y: h * 0.92)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: size / 2)
            .frame(width: size, height: size)
    }
}

/// One glass definition: blur, translucent fill, specular edge, rim, shadow.
struct GlassSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = Glass.panelRadius
    var level: Glass.Level = .panel

    private var solid: Bool { reduceTransparency || contrast == .increased }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if solid {
                shape.fill(level == .panel ? Glass.solid : Glass.solidInset)
                    .overlay { shape.strokeBorder(Glass.solidBorder, lineWidth: 1) }
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay { shape.fill(level == .panel ? Glass.fill : Glass.insetFill) }
                    // Specular edge: bright along the top, fading out.
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(colors: [Glass.edge, .clear], startPoint: .top, endPoint: .center),
                            lineWidth: 1)
                    }
                    // Rim.
                    .overlay { shape.strokeBorder(Glass.rim, lineWidth: 1) }
                    .shadow(color: level == .panel ? Glass.shadow : .clear, radius: 16, x: 0, y: 8)
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = Glass.panelRadius, level: Glass.Level = .panel) -> some View {
        background(GlassSurface(cornerRadius: cornerRadius, level: level))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func glassNavigationChrome() -> some View {
        modifier(GlassNavigationChrome())
    }

    func glassListSurface() -> some View {
        modifier(GlassCollectionSurface())
    }

    func glassFormSurface() -> some View {
        modifier(GlassCollectionSurface())
    }

    func glassPresentationSurface() -> some View {
        modifier(GlassPresentationChrome())
    }

    func glassTabBarChrome() -> some View {
        modifier(GlassTabBarChrome())
    }
}

private struct GlassCollectionSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(GlassBackdrop())
            .listRowBackground(GlassSurface(cornerRadius: Glass.panelRadius))
            .listRowSeparator(.hidden)
    }
}

private struct GlassPresentationChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .presentationBackground(
                reduceTransparency || contrast == .increased
                    ? AnyShapeStyle(Glass.solid)
                    : AnyShapeStyle(.regularMaterial)
            )
            .presentationCornerRadius(Glass.sheetRadius)
    }
}

private struct GlassTabBarChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .toolbarBackground(
                reduceTransparency || contrast == .increased
                    ? AnyShapeStyle(Glass.solid)
                    : AnyShapeStyle(.ultraThinMaterial),
                for: .tabBar
            )
            .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct GlassNavigationChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(GlassBackdrop())
            .toolbarBackground(
                reduceTransparency || contrast == .increased
                    ? AnyShapeStyle(Glass.solid)
                    : AnyShapeStyle(.ultraThinMaterial),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
