//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

/// Shared layout and styling helpers for the basic catalog components.
enum A2uiLayout {
    /// The spacing used between children of layout containers.
    static let spacing: CGFloat = 8

    /// The corner radius used by cards and inputs.
    static let cornerRadius: CGFloat = 12

    /// Maps an A2UI cross-axis alignment onto a SwiftUI horizontal alignment.
    static func horizontalAlignment(_ align: String) -> HorizontalAlignment {
        switch align {
        case "center": return .center
        case "end": return .trailing
        default: return .leading
        }
    }

    /// Maps an A2UI cross-axis alignment onto a SwiftUI vertical alignment.
    static func verticalAlignment(_ align: String) -> VerticalAlignment {
        switch align {
        case "center": return .center
        case "end": return .bottom
        default: return .top
        }
    }

    /// Maps an A2UI cross-axis alignment onto a SwiftUI frame alignment.
    static func frameAlignment(_ align: String, axis: Axis) -> Alignment {
        switch axis {
        case .horizontal:
            switch align {
            case "center": return .center
            case "end": return .bottom
            default: return .top
            }
        case .vertical:
            switch align {
            case "center": return .center
            case "end": return .trailing
            default: return .leading
            }
        }
    }

    /// Whether an A2UI main-axis distribution needs spacers between children.
    ///
    /// SwiftUI stacks have no direct equivalent of `space-between`, so the
    /// renderer inserts spacers to approximate the CSS behaviour. When a child
    /// declares a layout weight it already absorbs the free space, exactly as
    /// `flex-grow` does, so spacers are suppressed to avoid competing with it.
    static func spacersFor(justify: String, hasWeightedChild: Bool) -> (leading: Bool, between: Bool, trailing: Bool) {
        guard !hasWeightedChild else { return (false, false, false) }
        switch justify {
        case "center": return (true, false, true)
        case "end": return (true, false, false)
        case "spaceBetween": return (false, true, false)
        case "spaceAround", "spaceEvenly": return (true, true, true)
        default: return (false, false, true)
        }
    }
}

/// Applies the A2UI layout weight of a child inside a `Row` or `Column`.
///
/// A2UI weights follow the CSS `flex-grow` model: siblings keep their natural
/// size and the weighted child absorbs what is left. SwiftUI sizes
/// high-priority children first, so a weighted child is given a *lower* layout
/// priority than its siblings; without that, a weighted label starves a short
/// sibling such as a price into zero width.
///
/// Relative weights between several weighted children are not expressible in
/// SwiftUI's stack layout, so they share the remaining space equally.
struct WeightedChild: View {
    let child: ResolvedChild
    let content: AnyView
    let axis: Axis

    var body: some View {
        if let weight = child.weight, weight > 0 {
            content
                .frame(
                    maxWidth: axis == .horizontal ? .infinity : nil,
                    maxHeight: axis == .vertical ? .infinity : nil,
                    alignment: axis == .horizontal ? .leading : .top
                )
                .layoutPriority(-1)
        } else {
            content
        }
    }
}

/// Displays the failing checks of an input component.
struct ValidationMessages: View {
    let results: [ValidationResult]

    var body: some View {
        if results.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                    if let message = result.message ?? result.code {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(color(for: result.severity))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func color(for severity: ValidationResult.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }
}

/// A background color that works on every Apple platform.
enum A2uiColor {
    /// The fill used behind cards.
    static var cardBackground: Color {
        #if canImport(UIKit) && !os(watchOS)
        return Color(UIColor.secondarySystemBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color.gray.opacity(0.12)
        #endif
    }

    /// The fill used behind text inputs.
    static var inputBackground: Color {
        Color.gray.opacity(0.12)
    }
}
