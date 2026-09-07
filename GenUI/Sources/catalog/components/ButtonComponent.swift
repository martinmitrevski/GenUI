//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

/// The button component of the A2UI basic catalog.
public enum ButtonComponent {
    /// All button components, in catalog order.
    public static var all: [ComponentDefinition] {
        [button]
    }

    /// A button that dispatches an action when tapped.
    ///
    /// When the button declares `checks`, it disables itself while any check
    /// fails and shows the first failure message, as required by the
    /// specification's button validation behaviour.
    public static let button = ComponentDefinition(
        name: "Button",
        description: "A clickable button that dispatches an action. Supports 'primary' and 'borderless' variants.",
        properties: [
            "child": JsonSchema.child(
                description: "The ID of the child component. Use a 'Text' component for a labeled button. "
                    + "Only use an 'Icon' if the requirements explicitly ask for an icon-only button."
            ),
            "variant": JsonSchema.string(
                description: "A hint for the button style. 'primary' indicates the main call to action; "
                    + "'borderless' renders the child like a link.",
                enumValues: ["default", "primary", "borderless"],
                defaultValue: "default"
            ),
            "action": JsonSchema.action(),
            "checks": JsonSchema.array(
                description: "Checks that must pass for the button to be enabled.",
                items: JsonSchema.commonType("CheckRule")
            ),
            "weight": JsonSchema.weight()
        ],
        required: ["child", "action"],
        examples: [
            """
            [
              {
                "id": "root",
                "component": "Button",
                "child": "label",
                "variant": "primary",
                "action": {"event": {"name": "submit", "context": {}}}
              },
              {"id": "label", "component": "Text", "text": "Submit"}
            ]
            """
        ]
    ) { context in
        let failures = context.failingChecks
        let isDisabled = failures.contains { $0.severity == .error }

        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    context.performAction()
                } label: {
                    context.childView(context.childId())
                        .modifier(A2uiButtonLabelStyle(variant: context.option("variant", default: "default")))
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .opacity(isDisabled ? 0.5 : 1)
                ValidationMessages(results: failures)
            }
        )
    }
}

/// Applies the visual style of an A2UI button variant.
private struct A2uiButtonLabelStyle: ViewModifier {
    let variant: String

    func body(content: Content) -> some View {
        switch variant {
        case "primary":
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundColor(.white)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case "borderless":
            content
                .foregroundColor(.accentColor)
                .padding(.vertical, 4)
        default:
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
