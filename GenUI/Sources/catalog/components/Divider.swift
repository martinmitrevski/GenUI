//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

private struct DividerData {
    let axis: String?

    init(json: JsonMap) {
        self.axis = json["axis"] as? String
    }
}

public let divider = CatalogItem(
    name: "Divider",
    dataSchema: S.object(
        properties: ["axis": S.string(enumValues: ["horizontal", "vertical"]) ]
    ),
    widgetBuilder: { itemContext in
        let data = DividerData(json: itemContext.data as? JsonMap ?? [:])
        if data.axis == "vertical" {
            return AnyView(Rectangle().frame(width: 1).foregroundColor(.gray.opacity(0.3)))
        }
        return AnyView(Divider())
    },
    exampleData: [
        {
            """
            [
              {
                "id": "root",
                "component": {
                  "Divider": {}
                }
              }
            ]
            """
        }
    ]
)
