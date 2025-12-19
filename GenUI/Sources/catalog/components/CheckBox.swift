//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

private struct CheckBoxData {
    let label: JsonMap
    let value: JsonMap

    init(json: JsonMap) {
        self.label = json["label"] as? JsonMap ?? [:]
        self.value = json["value"] as? JsonMap ?? [:]
    }
}

public let checkBox = CatalogItem(
    name: "CheckBox",
    dataSchema: S.object(
        properties: [
            "label": A2uiSchemas.stringReference(),
            "value": A2uiSchemas.booleanReference()
        ],
        required: ["label", "value"]
    ),
    widgetBuilder: { itemContext in
        let data = CheckBoxData(json: itemContext.data as? JsonMap ?? [:])
        let labelNotifier = itemContext.dataContext.subscribeToString(data.label)
        let valueNotifier = itemContext.dataContext.subscribeToBool(data.value)

        return AnyView(
            OptionalValueBuilder(listenable: labelNotifier) { label in
                ValueObserverView(listenable: valueNotifier) { value in
                    Toggle(isOn: Binding(
                        get: { value ?? false },
                        set: { newValue in
                            valueNotifier.value = newValue
                            if let path = data.value["path"] as? String {
                                itemContext.dataContext.update(DataPath(path), newValue)
                            }
                        }
                    )) {
                        Text(label)
                    }
                }
            }
        )
    },
    exampleData: [
        {
            """
            [
              {
                "id": "root",
                "component": {
                  "CheckBox": {
                    "label": {
                      "literalString": "Check me"
                    },
                    "value": {
                      "path": "/myValue",
                      "literalBoolean": true
                    }
                  }
                }
              }
            ]
            """
        }
    ]
)
