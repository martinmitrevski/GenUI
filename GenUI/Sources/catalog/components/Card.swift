//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI
import UIKit

private struct CardData {
    let child: String

    init(json: JsonMap) {
        self.child = json["child"] as? String ?? ""
    }
}

public let card = CatalogItem(
    name: "Card",
    dataSchema: S.object(
        properties: ["child": A2uiSchemas.componentReference()],
        required: ["child"]
    ),
    widgetBuilder: { itemContext in
        let data = CardData(json: itemContext.data as? JsonMap ?? [:])
        return AnyView(
            itemContext.buildChild(data.child, nil)
                .padding(8)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
        )
    },
    exampleData: [
        {
            """
            [
              {
                "id": "root",
                "component": {
                  "Card": {
                    "child": "text"
                  }
                }
              },
              {
                "id": "text",
                "component": {
                  "Text": {
                    "text": {
                      "literalString": "This is a card."
                    }
                  }
                }
              }
            ]
            """
        }
    ]
)
