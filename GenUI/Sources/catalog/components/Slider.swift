//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

private struct SliderData {
    let value: JsonMap
    let minValue: Double
    let maxValue: Double

    init(json: JsonMap) {
        self.value = json["value"] as? JsonMap ?? [:]
        self.minValue = (json["minValue"] as? NSNumber)?.doubleValue ?? 0.0
        self.maxValue = (json["maxValue"] as? NSNumber)?.doubleValue ?? 1.0
    }
}

public let slider = CatalogItem(
    name: "Slider",
    dataSchema: S.object(
        properties: [
            "value": A2uiSchemas.numberReference(),
            "minValue": S.number(),
            "maxValue": S.number()
        ],
        required: ["value"]
    ),
    widgetBuilder: { itemContext in
        let data = SliderData(json: itemContext.data as? JsonMap ?? [:])
        let notifier: ValueNotifier<Double?> = itemContext.dataContext.subscribeToValue(data.value, literalKey: "literalNumber")

        return AnyView(
            ValueObserverView(listenable: notifier) { value in
                let currentValue = value ?? data.minValue
                return HStack {
                    Slider(
                        value: Binding(
                            get: { currentValue },
                            set: { newValue in
                                notifier.value = newValue
                                if let path = data.value["path"] as? String {
                                    itemContext.dataContext.update(DataPath(path), newValue)
                                }
                            }
                        ),
                        in: data.minValue...data.maxValue
                    )
                    Text(String(format: "%.0f", currentValue))
                        .frame(minWidth: 40)
                }
                .padding(.trailing, 16)
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
                  "Slider": {
                    "minValue": 0,
                    "maxValue": 10,
                    "value": {
                      "path": "/myValue",
                      "literalNumber": 5
                    }
                  }
                }
              }
            ]
            """
        }
    ]
)
