//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

private struct ButtonData {
    let child: String
    let action: JsonMap
    let primary: Bool

    init(json: JsonMap) {
        self.child = json["child"] as? String ?? ""
        self.action = json["action"] as? JsonMap ?? [:]
        self.primary = json["primary"] as? Bool ?? false
    }
}

private let buttonSchema = S.object(
    properties: [
        "child": A2uiSchemas.componentReference(
            description: "The ID of a child widget. This should always be set, e.g. to the ID of a `Text` widget."
        ),
        "action": A2uiSchemas.action(),
        "primary": S.boolean(description: "Whether the button invokes a primary action.")
    ],
    required: ["child", "action"]
)

public let button = CatalogItem(
    name: "Button",
    dataSchema: buttonSchema,
    widgetBuilder: { itemContext in
        let buttonData = ButtonData(json: itemContext.data as? JsonMap ?? [:])
        let childView = itemContext.buildChild(buttonData.child, nil)
        let actionName = buttonData.action["name"] as? String ?? ""
        let contextDefinition = buttonData.action["context"] as? [Any] ?? []

        return AnyView(
            Button(action: {
                let resolvedContext = resolveContext(itemContext.dataContext, contextDefinition)
                itemContext.dispatchEvent(
                    UserActionEvent(
                        name: actionName,
                        sourceComponentId: itemContext.id,
                        context: resolvedContext
                    )
                )
            }) {
                childView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .background(buttonData.primary ? Color.accentColor : Color.gray.opacity(0.1))
            .foregroundColor(buttonData.primary ? Color.white : Color.primary)
            .cornerRadius(8)
        )
    },
    exampleData: [
        {
            """
            [
              {
                "id": "root",
                "component": {
                  "Button": {
                    "child": "text",
                    "action": {
                      "name": "button_pressed"
                    }
                  }
                }
              },
              {
                "id": "text",
                "component": {
                  "Text": {
                    "text": {
                      "literalString": "Hello World"
                    }
                  }
                }
              }
            ]
            """
        }
    ]
)
