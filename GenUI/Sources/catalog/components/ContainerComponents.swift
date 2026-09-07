//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

/// The composite container components of the A2UI basic catalog.
public enum ContainerComponents {
    /// All container components, in catalog order.
    public static var all: [ComponentDefinition] {
        [tabs, modal]
    }

    /// A set of tabs, each with a title and a child component.
    public static let tabs = ComponentDefinition(
        name: "Tabs",
        description: "A set of tabs, each with a title and child component.",
        properties: [
            "tabs": JsonSchema.array(
                description: "An array of objects, where each object defines a tab with a title and a child component.",
                items: JsonSchema.object(
                    properties: [
                        "title": JsonSchema.dynamicString(description: "The tab title."),
                        "child": JsonSchema.child(description: "The ID of the child component.")
                    ],
                    required: ["title", "child"],
                    additionalProperties: false
                ),
                minItems: 1
            ),
            "weight": JsonSchema.weight()
        ],
        required: ["tabs"],
        examples: [
            """
            [
              {
                "id": "root",
                "component": "Tabs",
                "tabs": [
                  {"title": "Details", "child": "details"},
                  {"title": "Reviews", "child": "reviews"}
                ]
              },
              {"id": "details", "component": "Text", "text": "Details"},
              {"id": "reviews", "component": "Text", "text": "Reviews"}
            ]
            """
        ]
    ) { context in
        let items = (Json.array(context.component.property("tabs")) ?? []).compactMap { entry -> A2uiTab? in
            guard let map = Json.map(entry), let child = map["child"] as? String else { return nil }
            let title = context.evaluator.string(DynamicValue(map["title"]), in: context.dataContext) ?? ""
            return A2uiTab(title: title, childId: child)
        }
        return AnyView(A2uiTabsView(tabs: items, context: context))
    }

    /// A dialog opened by a trigger component.
    ///
    /// The trigger is rendered inline; interacting with it presents the content
    /// as a sheet. The trigger's own action, if it has one, still fires.
    public static let modal = ComponentDefinition(
        name: "Modal",
        description: "A dialog that appears over the main content, triggered by a component in the main content.",
        properties: [
            "trigger": JsonSchema.child(
                description: "The ID of the component that opens the modal when interacted with (e.g., a button)."
            ),
            "content": JsonSchema.child(description: "The ID of the component to be displayed inside the modal."),
            "weight": JsonSchema.weight()
        ],
        required: ["trigger", "content"],
        examples: [
            """
            [
              {"id": "root", "component": "Modal", "trigger": "openButton", "content": "details"},
              {
                "id": "openButton",
                "component": "Button",
                "child": "openLabel",
                "action": {"event": {"name": "open_details", "context": {}}}
              },
              {"id": "openLabel", "component": "Text", "text": "Details"},
              {"id": "details", "component": "Text", "text": "More information."}
            ]
            """
        ]
    ) { context in
        AnyView(
            A2uiModalView(
                trigger: context.childView(context.childId("trigger")),
                content: context.childView(context.childId("content"))
            )
        )
    }
}

/// One entry of an A2UI `Tabs` component.
private struct A2uiTab: Identifiable {
    let title: String
    let childId: String

    var id: String { childId }
}

/// Renders tab headers and the selected tab's content.
///
/// A custom header is used instead of `TabView` so that tabs compose inside
/// scrollable agent-driven layouts.
private struct A2uiTabsView: View {
    let tabs: [A2uiTab]
    let context: ComponentRenderContext

    @State private var selection: String?

    var body: some View {
        let selected = selection ?? tabs.first?.id

        return VStack(alignment: .leading, spacing: A2uiLayout.spacing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabs) { tab in
                        Button {
                            selection = tab.id
                        } label: {
                            Text(tab.title)
                                .font(.subheadline.weight(selected == tab.id ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selected == tab.id ? Color.accentColor.opacity(0.15) : Color.clear
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == tab.id ? [.isSelected, .isButton] : .isButton)
                    }
                }
            }
            if let selected, let tab = tabs.first(where: { $0.id == selected }) {
                context.childView(tab.childId)
            }
        }
    }
}

/// Presents modal content when its trigger is interacted with.
private struct A2uiModalView: View {
    let trigger: AnyView
    let content: AnyView

    @State private var isPresented = false

    var body: some View {
        trigger
            .simultaneousGesture(TapGesture().onEnded {
                isPresented = true
            })
            .sheet(isPresented: $isPresented) {
                #if os(iOS) || os(tvOS)
                NavigationView {
                    ScrollView {
                        content.padding()
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { isPresented = false }
                        }
                    }
                }
                #else
                VStack(alignment: .trailing) {
                    Button("Close") { isPresented = false }
                    ScrollView { content }
                }
                .padding()
                .frame(minWidth: 320, minHeight: 240)
                #endif
            }
    }
}
