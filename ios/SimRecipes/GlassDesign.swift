import SwiftUI
import UIKit

/// The shared surface language for recipe, camera, and account workflows.
struct GlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            if !reduceTransparency {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.035), lineWidth: 1)
                    .frame(width: 300, height: 300)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.025), lineWidth: 1)
                            .padding(18)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 110, y: 110)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }
}

struct GlassSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(reduceTransparency
                ? AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
                : AnyShapeStyle(.ultraThinMaterial))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(reduceTransparency ? 0.14 : 0.08), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        background(GlassSurface(cornerRadius: cornerRadius))
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
            .listRowBackground(GlassSurface(cornerRadius: 16))
            .listRowSeparator(.hidden)
    }
}

private struct GlassPresentationChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.presentationBackground(
            reduceTransparency
                ? AnyShapeStyle(Color(uiColor: .systemGroupedBackground))
                : AnyShapeStyle(.regularMaterial)
        )
    }
}

private struct GlassTabBarChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .toolbarBackground(
                reduceTransparency
                    ? AnyShapeStyle(Color(uiColor: .systemBackground))
                    : AnyShapeStyle(.ultraThinMaterial),
                for: .tabBar
            )
            .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct GlassNavigationChrome: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(GlassBackdrop())
            .toolbarBackground(
                reduceTransparency
                    ? AnyShapeStyle(Color(uiColor: .systemBackground))
                    : AnyShapeStyle(.ultraThinMaterial),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
