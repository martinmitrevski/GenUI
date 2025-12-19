//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

private struct TextData {
    let text: JsonMap
    let usageHint: String?

    init(json: JsonMap) {
        self.text = json["text"] as? JsonMap ?? [:]
        self.usageHint = json["usageHint"] as? String
    }
}

public let text = CatalogItem(
    name: "Text",
    dataSchema: S.object(
        properties: [
            "text": A2uiSchemas.stringReference(
                description: "While simple Markdown is supported (without HTML or image references), utilizing dedicated UI components is generally preferred for a richer and more structured presentation."
            ),
            "usageHint": S.string(
                description: "A usage hint for the base text style.",
                enumValues: ["h1", "h2", "h3", "h4", "h5", "caption", "body"]
            )
        ],
        required: ["text"]
    ),
    widgetBuilder: { itemContext in
        let textData = TextData(json: itemContext.data as? JsonMap ?? [:])
        let notifier = itemContext.dataContext.subscribeToString(textData.text)

        return AnyView(OptionalValueBuilder(listenable: notifier) { value in
            let font: Font
            switch textData.usageHint {
            case "h1": font = .largeTitle
            case "h2": font = .title
            case "h3": font = .title2
            case "h4": font = .title3
            case "h5": font = .headline
            case "caption": font = .caption
            default: font = .body
            }
            return Text(value)
                .font(font)
                .padding(.vertical, verticalPadding(for: textData.usageHint))
        })
    },
    exampleData: [
        {
            """
            [
              {
                "id": "root",
                "component": {
                  "Text": {
                    "text": {
                      "literalString": "Hello World"
                    },
                    "usageHint": "h1"
                  }
                }
              }
            ]
            """
        }
    ]
)

private func verticalPadding(for usageHint: String?) -> CGFloat {
    switch usageHint {
    case "h1": return 20
    case "h2": return 16
    case "h3": return 12
    case "h4": return 8
    case "h5": return 4
    default: return 0
    }
}
